import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Sigurno čuvanje tokena na uređaju.
///
/// `flutter_secure_storage` čuva podatke šifrovano (Keychain na iOS,
/// EncryptedSharedPreferences na Android). Tu držimo JWT tokene i ulogu.
class TokenStorage {
  // Ključevi pod kojima čuvamo vrijednosti.
  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _roleKey = 'user_role';
  static const _employeeIdKey = 'employee_id';

  final FlutterSecureStorage _storage;

  // Konstruktor sa podrazumijevanom instancom (lakše za testiranje).
  TokenStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  /// Sačuvaj sve tokene odjednom (nakon prijave ili osvježavanja).
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    String? role,
    int? employeeId,
  }) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
    if (role != null) {
      await _storage.write(key: _roleKey, value: role);
    }
    if (employeeId != null) {
      await _storage.write(key: _employeeIdKey, value: employeeId.toString());
    }
  }

  Future<String?> get accessToken => _storage.read(key: _accessTokenKey);

  Future<String?> get refreshToken => _storage.read(key: _refreshTokenKey);

  Future<String?> get role => _storage.read(key: _roleKey);

  /// ID prijavljenog zaposlenog (ili null ako nije sačuvan).
  Future<int?> get employeeId async {
    final value = await _storage.read(key: _employeeIdKey);
    return value == null ? null : int.tryParse(value);
  }

  /// Da li je korisnik prijavljen (ima li sačuvan refresh token).
  Future<bool> get isLoggedIn async => (await refreshToken) != null;

  /// Obriši sve — koristi se pri odjavi.
  Future<void> clear() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _roleKey);
    await _storage.delete(key: _employeeIdKey);
  }
}
