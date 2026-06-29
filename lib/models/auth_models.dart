import 'package:freezed_annotation/freezed_annotation.dart';

// Ove dvije linije govore generatoru gdje da upiše dopunjeni kod.
// Fajlovi se kreiraju komandom: dart run build_runner build
part 'auth_models.freezed.dart';
part 'auth_models.g.dart';

/// Podaci koje šaljemo pri prijavi (POST /api/auth/login).
@freezed
class LoginRequest with _$LoginRequest {
  const factory LoginRequest({
    required String username,
    required String password,
    String? deviceLabel,
  }) = _LoginRequest;

  factory LoginRequest.fromJson(Map<String, dynamic> json) =>
      _$LoginRequestFromJson(json);
}

/// Zahtjev za osvježavanje tokena (POST /api/auth/refresh).
@freezed
class RefreshRequest with _$RefreshRequest {
  const factory RefreshRequest({
    required String refreshToken,
    String? deviceLabel,
  }) = _RefreshRequest;

  factory RefreshRequest.fromJson(Map<String, dynamic> json) =>
      _$RefreshRequestFromJson(json);
}

/// Zahtjev za odjavu (POST /api/auth/logout).
@freezed
class LogoutRequest with _$LogoutRequest {
  const factory LogoutRequest({
    required String refreshToken,
  }) = _LogoutRequest;

  factory LogoutRequest.fromJson(Map<String, dynamic> json) =>
      _$LogoutRequestFromJson(json);
}

/// Odgovor servera sa tokenima i podacima o ulozi korisnika.
/// Ovo dobijamo nakon uspješne prijave ili osvježavanja.
@freezed
class TokenPair with _$TokenPair {
  const factory TokenPair({
    String? accessToken,
    int? accessExpiresInSeconds,
    String? refreshToken,
    DateTime? refreshExpiresAt,
    String? role, // Uloga korisnika (npr. ADMIN, EMPLOYEE) — koristi se za navigaciju.
    int? employeeId,
    int? sellingPlaceId,
  }) = _TokenPair;

  factory TokenPair.fromJson(Map<String, dynamic> json) =>
      _$TokenPairFromJson(json);
}
