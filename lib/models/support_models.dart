import 'package:freezed_annotation/freezed_annotation.dart';

part 'support_models.freezed.dart';
part 'support_models.g.dart';

/// Jedan salon (prodajno mjesto) u „support" listi firmi.
@freezed
class SupportSellingPlace with _$SupportSellingPlace {
  const factory SupportSellingPlace({
    int? id,
    String? name,
    String? address,
  }) = _SupportSellingPlace;

  factory SupportSellingPlace.fromJson(Map<String, dynamic> json) =>
      _$SupportSellingPlaceFromJson(json);
}

/// Jedna firma (tenant) sa svojim salonima — GET /api/support/businesses.
@freezed
class SupportBusiness with _$SupportBusiness {
  const factory SupportBusiness({
    int? id,
    String? name,
    String? status,
    @Default([]) List<SupportSellingPlace> sellingPlaces,
  }) = _SupportBusiness;

  factory SupportBusiness.fromJson(Map<String, dynamic> json) =>
      _$SupportBusinessFromJson(json);
}

/// Zahtjev za ulazak u salon (POST /api/support/impersonate).
@freezed
class ImpersonateRequest with _$ImpersonateRequest {
  const factory ImpersonateRequest({
    required int sellingPlaceId,
  }) = _ImpersonateRequest;

  factory ImpersonateRequest.fromJson(Map<String, dynamic> json) =>
      _$ImpersonateRequestFromJson(json);
}

/// Odgovor pri ulasku u salon — nosi IMPERSONATION token + info o salonu.
/// (Nema refresh token — po dizajnu; ne perzistira kroz /api/auth/refresh.)
@freezed
class ImpersonationResponse with _$ImpersonationResponse {
  const factory ImpersonationResponse({
    String? accessToken,
    int? accessExpiresInSeconds,
    int? businessId,
    String? businessName,
    int? sellingPlaceId,
    String? sellingPlaceName,
  }) = _ImpersonationResponse;

  factory ImpersonationResponse.fromJson(Map<String, dynamic> json) =>
      _$ImpersonationResponseFromJson(json);
}
