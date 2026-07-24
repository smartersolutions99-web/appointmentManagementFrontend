import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config.dart';
import '../core/exceptions.dart';
import '../models/models.dart';
import 'api_service.dart';
import 'providers.dart';
import 'token_storage.dart';

/// Mogući statusi sesije korisnika.
enum AuthStatus {
  unknown, // Još provjeravamo da li je korisnik prijavljen (na startu).
  authenticated, // Prijavljen.
  unauthenticated, // Nije prijavljen.
}

/// Upravlja prijavom, odjavom i informacijom o ulozi korisnika.
///
/// `ChangeNotifier` znači: kada pozovemo `notifyListeners()`, svi koji slušaju
/// (uključujući GoRouter) saznaju za promjenu i reaguju (npr. preusmjere ekran).
class AuthController extends ChangeNotifier {
  final TokenStorage _storage;
  final Ref _ref; // Da bismo „lijeno“ dohvatili ApiService kada zatreba.

  AuthStatus status = AuthStatus.unknown;
  String? role; // Uloga korisnika (npr. "ADMIN", "EMPLOYEE").
  int? employeeId; // ID prijavljenog zaposlenog (za „zakucavanje“ termina).

  AuthController(this._storage, this._ref) {
    _loadFromStorage(); // Na startu provjeri da li smo već prijavljeni.
  }

  /// Da li je korisnik administrator (utiče na prikaz menija).
  bool get isAdmin => (role ?? '').toUpperCase().contains('ADMIN');

  // ApiService dohvatamo tek kada nam treba (izbjegavamo zavisnost u krug).
  ApiService get _api => _ref.read(apiServiceProvider);

  /// Pri pokretanju aplikacije: ako postoji sačuvan token — smatramo da smo
  /// prijavljeni (interceptor će po potrebi osvježiti token).
  Future<void> _loadFromStorage() async {
    final loggedIn = await _storage.isLoggedIn;
    role = await _storage.role;
    employeeId = await _storage.employeeId;
    status = loggedIn ? AuthStatus.authenticated : AuthStatus.unauthenticated;
    notifyListeners();
  }

  /// Prijava korisnika. Vraća poruku greške ili `null` ako je uspjelo.
  Future<String?> login(String username, String password) async {
    try {
      final tokens = await _api.login(
        LoginRequest(
          username: username,
          password: password,
          deviceLabel: AppConfig.deviceLabel,
        ),
      );

      // Bez tokena nema prijave.
      if (tokens.accessToken == null || tokens.refreshToken == null) {
        return 'Server nije vratio ispravne tokene.';
      }

      await _storage.saveTokens(
        accessToken: tokens.accessToken!,
        refreshToken: tokens.refreshToken!,
        role: tokens.role,
        employeeId: tokens.employeeId,
        username: username,
      );

      role = tokens.role;
      employeeId = tokens.employeeId;
      status = AuthStatus.authenticated;
      notifyListeners();
      return null; // null = uspjeh
    } catch (e) {
      // Pretvaramo grešku u razumljivu poruku za korisnika.
      return ApiException.from(e).message;
    }
  }

  /// Ponovna provjera lozinke (za pristup osjetljivim stranicama — Izvještaji,
  /// Zaposleni). Provjerava se PONOVNOM prijavom sa sačuvanim korisničkim imenom
  /// i unesenom lozinkom (server je autoritet). Na uspjeh se tokeni osvježe
  /// bešavno; na neuspjeh se ništa ne mijenja. Vraća `true` ako je lozinka tačna.
  Future<bool> verifyPassword(String password) async {
    final user = await _storage.username;
    if (user == null || user.isEmpty) return false;
    try {
      final tokens = await _api.login(
        LoginRequest(
          username: user,
          password: password,
          deviceLabel: AppConfig.deviceLabel,
        ),
      );
      if (tokens.accessToken == null || tokens.refreshToken == null) {
        return false;
      }
      // Bešavno osvježi tokene (status/uloga se ne mijenjaju, pa NE zovemo
      // notifyListeners — da ne pokrenemo osvježavanje router-a dok traje dijalog).
      await _storage.saveTokens(
        accessToken: tokens.accessToken!,
        refreshToken: tokens.refreshToken!,
        role: tokens.role,
        employeeId: tokens.employeeId,
        username: user,
      );
      return true;
    } catch (_) {
      return false; // pogrešna lozinka ili greška — trenutna sesija netaknuta
    }
  }

  /// Odjava — obavještava server (best-effort) i briše lokalne tokene.
  Future<void> logout() async {
    try {
      final refreshToken = await _storage.refreshToken;
      if (refreshToken != null) {
        await _api.logout(LogoutRequest(refreshToken: refreshToken));
      }
    } catch (_) {
      // Čak i ako poziv ka serveru ne uspije, lokalno se ipak odjavljujemo.
    }
    await _storage.clear();
    role = null;
    employeeId = null;
    status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  /// Poziva interceptor kada refresh konačno ne uspije (sesija istekla).
  void handleSessionExpired() {
    role = null;
    employeeId = null;
    status = AuthStatus.unauthenticated;
    notifyListeners();
  }
}
