import 'dart:async';

import 'package:dio/dio.dart';

import '../core/config.dart';
import 'support_session.dart';
import 'token_storage.dart';

/// Interceptor koji se „umiješa“ u svaki mrežni zahtjev.
///
/// 1. Na svaki zahtjev dodaje `Authorization: Bearer <token>`.
///    - `/api/auth/*` → bez tokena;
///    - `/api/support/*` → uvijek ROOT token (SUPER_SUPER_ADMIN);
///    - ostalo (salon-pozivi) → IMPERSONATION token ako smo u „support modu",
///      inače običan (root/korisnički) token.
/// 2. Na 401 pokušava oporavak:
///    - obični korisnik / support pozivi → `/api/auth/refresh` pa ponovi zahtjev;
///    - salon-poziv u support modu → osvježi root (po potrebi) + ponovo uđi u
///      salon (`/api/support/impersonate`) pa ponovi zahtjev; ako ne uspije,
///      vrati korisnika na salon-picker.
///
/// NAPOMENA: za OBIČNE korisnike (impersonation token == null) ponašanje je
/// identično kao ranije — bira se root token i standardni refresh.
class AuthInterceptor extends Interceptor {
  final TokenStorage _tokenStorage;
  final SupportSession _support;

  /// Poseban Dio bez interceptora — koristimo ga za /refresh i /impersonate,
  /// da ne upadnemo u beskonačnu petlju.
  final Dio _refreshDio;

  /// Poziva se kad sesija konačno istekne (vrati na login).
  final void Function()? onSessionExpired;

  /// Poziva se kad impersonacija propadne (vrati na salon-picker).
  final void Function()? onImpersonationLost;

  /// „Brave“ koje sprječavaju paralelni refresh / re-impersonaciju.
  Completer<String?>? _refreshCompleter;
  Completer<String?>? _reimpersonateCompleter;

  AuthInterceptor(
    this._tokenStorage,
    this._support, {
    this.onSessionExpired,
    this.onImpersonationLost,
  }) : _refreshDio = Dio(BaseOptions(
          baseUrl: AppConfig.baseUrl,
          contentType: Headers.jsonContentType,
          headers: const {'Accept': 'application/json'},
        ));

  bool _isAuthPath(String path) => path.contains('/api/auth/');
  bool _isSupportPath(String path) => path.contains('/api/support/');

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final path = options.path;

    // Na auth rute (login/refresh) ne kačimo token.
    if (_isAuthPath(path)) {
      handler.next(options);
      return;
    }

    String? token;
    if (_isSupportPath(path)) {
      // /api/support/* uvijek koristi ROOT token.
      token = await _tokenStorage.accessToken;
    } else {
      // Salon-poziv: u support modu impersonation token; inače običan token.
      token = _support.token ?? await _tokenStorage.accessToken;
    }
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final path = err.requestOptions.path;
    final isUnauthorized = err.response?.statusCode == 401;

    // Refresh/oporavak pokušavamo samo na 401 i NE na auth pozivima.
    if (!isUnauthorized || _isAuthPath(path)) {
      return handler.next(err);
    }

    // Salon-poziv koji je pao na 401 DOK smo u support modu → re-impersonacija.
    if (_support.active && !_isSupportPath(path)) {
      try {
        final newImp = await _reimpersonate();
        if (newImp == null) {
          _support.clear();
          onImpersonationLost?.call();
          return handler.next(err);
        }
        final retry = await _retryRequest(err.requestOptions, newImp);
        return handler.resolve(retry);
      } catch (_) {
        _support.clear();
        onImpersonationLost?.call();
        return handler.next(err);
      }
    }

    // Standardni refresh: obični korisnik ILI /api/support/* sa isteklim root tokenom.
    try {
      final newToken = await _refreshAccessToken();
      if (newToken == null) {
        await _tokenStorage.clear();
        onSessionExpired?.call();
        return handler.next(err);
      }
      final retryResponse = await _retryRequest(err.requestOptions, newToken);
      return handler.resolve(retryResponse);
    } catch (_) {
      await _tokenStorage.clear();
      onSessionExpired?.call();
      return handler.next(err);
    }
  }

  // ===================== RE-IMPERSONACIJA (support mode) =====================

  /// Ponovo uđi u isti salon (uz zaključavanje da se ne radi paralelno).
  Future<String?> _reimpersonate() {
    final existing = _reimpersonateCompleter;
    if (existing != null) return existing.future;

    final completer = Completer<String?>();
    _reimpersonateCompleter = completer;
    _doReimpersonate().then(completer.complete).catchError((Object _) {
      completer.complete(null);
    }).whenComplete(() => _reimpersonateCompleter = null);
    return completer.future;
  }

  Future<String?> _doReimpersonate() async {
    final placeId = _support.sellingPlaceId;
    if (placeId == null) return null;

    // Prvo probaj sa trenutnim root tokenom; na 401 osvježi root pa ponovo.
    final rootAccess = await _tokenStorage.accessToken;
    try {
      return await _callImpersonate(placeId, rootAccess);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        final newRoot = await _refreshAccessToken();
        if (newRoot == null) return null;
        return await _callImpersonate(placeId, newRoot);
      }
      return null;
    }
  }

  Future<String?> _callImpersonate(
      int sellingPlaceId, String? rootAccess) async {
    final resp = await _refreshDio.post<Map<String, dynamic>>(
      '/api/support/impersonate',
      data: {'sellingPlaceId': sellingPlaceId},
      options: Options(headers: {
        if (rootAccess != null) 'Authorization': 'Bearer $rootAccess',
      }),
    );
    final data = resp.data;
    if (data == null) return null;
    _support.updateFromMap(data);
    return _support.token;
  }

  // ===================== STANDARDNI REFRESH (root/korisnik) =====================

  /// Vraća novi access token (ili sačeka refresh koji je već u toku).
  Future<String?> _refreshAccessToken() {
    final existing = _refreshCompleter;
    if (existing != null) return existing.future;

    final completer = Completer<String?>();
    _refreshCompleter = completer;
    _doRefresh().then(completer.complete).catchError((Object _) {
      completer.complete(null);
    }).whenComplete(() => _refreshCompleter = null);
    return completer.future;
  }

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

    await _tokenStorage.saveTokens(
      accessToken: newAccess,
      refreshToken: newRefresh,
      role: role,
      employeeId: employeeId,
    );
    return newAccess;
  }

  /// Ponavlja originalni zahtjev sa datim tokenom u zaglavlju (bez interceptora).
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
