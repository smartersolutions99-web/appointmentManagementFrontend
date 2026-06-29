import 'dart:async';

import 'package:dio/dio.dart';

import '../core/config.dart';
import 'token_storage.dart';

/// Interceptor koji se „umiješa“ u svaki mrežni zahtjev.
///
/// Radi dvije ključne stvari:
/// 1. Na svaki zahtjev dodaje `Authorization: Bearer <token>`.
/// 2. Ako server vrati 401 (token istekao), automatski pokušava da osvježi
///    token preko /api/auth/refresh, pa ponavlja originalni zahtjev.
class AuthInterceptor extends Interceptor {
  final TokenStorage _tokenStorage;

  /// Poseban Dio bez interceptora — koristimo ga SAMO za /refresh poziv,
  /// da ne upadnemo u beskonačnu petlju osvježavanja.
  final Dio _refreshDio;

  /// Funkcija koja se poziva kada sesija konačno istekne (npr. da nas vrati
  /// na ekran za prijavu). Postavlja se izvana.
  final void Function()? onSessionExpired;

  /// „Brava“ koja sprječava da više zahtjeva istovremeno pokrene refresh.
  /// Ako je refresh u toku, ostali zahtjevi sačekaju isti rezultat.
  Completer<String?>? _refreshCompleter;

  AuthInterceptor(
    this._tokenStorage, {
    this.onSessionExpired,
  }) : _refreshDio = Dio(BaseOptions(
          baseUrl: AppConfig.baseUrl,
          // Isto kao kod glavnog klijenta: obavezno JSON, da refresh poziv
          // ne bude poslat kao 'application/octet-stream'.
          contentType: Headers.jsonContentType,
          headers: const {'Accept': 'application/json'},
        ));

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Na auth rute (login/refresh) ne kačimo token.
    final isAuthPath = options.path.contains('/api/auth/');
    if (!isAuthPath) {
      final token = await _tokenStorage.accessToken;
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options); // Pusti zahtjev dalje.
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;
    final isUnauthorized = response?.statusCode == 401;
    final isAuthPath = err.requestOptions.path.contains('/api/auth/');

    // Pokušavamo refresh samo ako je 401 i ako to NIJE bio auth poziv.
    if (!isUnauthorized || isAuthPath) {
      return handler.next(err);
    }

    try {
      // Dobij novi token (ili sačekaj refresh koji je već u toku).
      final newToken = await _refreshAccessToken();

      if (newToken == null) {
        // Refresh nije uspio — sesija je gotova.
        await _tokenStorage.clear();
        onSessionExpired?.call();
        return handler.next(err);
      }

      // Ponovi originalni zahtjev sa novim tokenom.
      final retryResponse = await _retryRequest(err.requestOptions, newToken);
      return handler.resolve(retryResponse);
    } catch (_) {
      // Bilo kakva greška u procesu — odjavi korisnika.
      await _tokenStorage.clear();
      onSessionExpired?.call();
      return handler.next(err);
    }
  }

  /// Vraća novi access token. Ako je refresh već pokrenut iz drugog zahtjeva,
  /// samo sačeka njegov rezultat (zahvaljujući `_refreshCompleter`).
  Future<String?> _refreshAccessToken() {
    // Ako refresh već traje, vrati isti „future“ svima.
    final existing = _refreshCompleter;
    if (existing != null) return existing.future;

    final completer = Completer<String?>();
    _refreshCompleter = completer;

    // Pokreni stvarni refresh i kad završi, oslobodi bravu.
    _doRefresh().then((token) {
      completer.complete(token);
    }).catchError((Object e) {
      completer.complete(null);
    }).whenComplete(() {
      _refreshCompleter = null;
    });

    return completer.future;
  }

  /// Stvarni poziv ka /api/auth/refresh.
  Future<String?> _doRefresh() async {
    final refreshToken = await _tokenStorage.refreshToken;
    if (refreshToken == null) return null;

    final response = await _refreshDio.post<Map<String, dynamic>>(
      '/api/auth/refresh',
      data: {
        'refreshToken': refreshToken,
        'deviceLabel': AppConfig.deviceLabel,
      },
    );

    final data = response.data;
    if (data == null) return null;

    final newAccess = data['accessToken'] as String?;
    final newRefresh = data['refreshToken'] as String?;
    final role = data['role'] as String?;
    final employeeId = (data['employeeId'] as num?)?.toInt();

    if (newAccess == null || newRefresh == null) return null;

    // Sačuvaj nove tokene za buduće zahtjeve.
    await _tokenStorage.saveTokens(
      accessToken: newAccess,
      refreshToken: newRefresh,
      role: role,
      employeeId: employeeId,
    );
    return newAccess;
  }

  /// Ponavlja originalni zahtjev, ali sa novim tokenom u zaglavlju.
  Future<Response<dynamic>> _retryRequest(
    RequestOptions requestOptions,
    String newToken,
  ) {
    final options = Options(
      method: requestOptions.method,
      headers: {
        ...requestOptions.headers,
        'Authorization': 'Bearer $newToken',
      },
    );

    return _refreshDio.request<dynamic>(
      requestOptions.path,
      data: requestOptions.data,
      queryParameters: requestOptions.queryParameters,
      options: options,
    );
  }
}
