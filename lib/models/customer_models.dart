import 'package:freezed_annotation/freezed_annotation.dart';

part 'customer_models.freezed.dart';
part 'customer_models.g.dart';

/// Podaci za kreiranje/izmjenu klijenta (POST/PUT /api/customers).
@freezed
class CustomerRequest with _$CustomerRequest {
  const factory CustomerRequest({
    required String name,
    required String contactValue, // telefon ili email
    String? contactType, // npr. "PHONE" ili "EMAIL"
    int? sellingPlaceId,
  }) = _CustomerRequest;

  factory CustomerRequest.fromJson(Map<String, dynamic> json) =>
      _$CustomerRequestFromJson(json);
}

/// Klijent kako ga vraća server.
@freezed
class CustomerResponse with _$CustomerResponse {
  const factory CustomerResponse({
    int? id,
    String? name,
    String? contactType,
    String? contactValue,
    int? sellingPlaceId,
  }) = _CustomerResponse;

  factory CustomerResponse.fromJson(Map<String, dynamic> json) =>
      _$CustomerResponseFromJson(json);
}

/// Rezultat pretrage klijenta po imenu (GET /api/customers/search).
@freezed
class CustomerSearchHit with _$CustomerSearchHit {
  const factory CustomerSearchHit({
    String? name,
    String? phone,
  }) = _CustomerSearchHit;

  factory CustomerSearchHit.fromJson(Map<String, dynamic> json) =>
      _$CustomerSearchHitFromJson(json);
}

/// Jedna stranica klijenata (paginacija) — vraća GET /api/customers.
///
/// Server vraća više polja, ali nama trebaju samo ova za prikaz i paginaciju.
@freezed
class PageCustomerResponse with _$PageCustomerResponse {
  const factory PageCustomerResponse({
    @Default([]) List<CustomerResponse> content, // klijenti na ovoj stranici
    @Default(0) int totalPages,
    @Default(0) int totalElements,
    @Default(0) int number, // redni broj trenutne stranice (počinje od 0)
    @Default(true) bool last, // da li je ovo posljednja stranica
  }) = _PageCustomerResponse;

  factory PageCustomerResponse.fromJson(Map<String, dynamic> json) =>
      _$PageCustomerResponseFromJson(json);
}
