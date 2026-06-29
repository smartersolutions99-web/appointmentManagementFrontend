import 'package:freezed_annotation/freezed_annotation.dart';

part 'product_models.freezed.dart';
part 'product_models.g.dart';

/// Podaci za kreiranje/izmjenu proizvoda.
@freezed
class ProductRequest with _$ProductRequest {
  const factory ProductRequest({
    String? name,
    double? price, // nabavna cijena
    double? finalPrice, // prodajna cijena
    int? supplierId,
    String? description,
  }) = _ProductRequest;

  factory ProductRequest.fromJson(Map<String, dynamic> json) =>
      _$ProductRequestFromJson(json);
}

/// Proizvod kako ga vraća server.
@freezed
class ProductResponse with _$ProductResponse {
  const factory ProductResponse({
    int? id,
    String? name,
    double? price,
    double? finalPrice,
    int? supplierId,
    String? description,
  }) = _ProductResponse;

  factory ProductResponse.fromJson(Map<String, dynamic> json) =>
      _$ProductResponseFromJson(json);
}

/// Dobavljač — koristi se za padajuću listu pri unosu proizvoda.
@freezed
class SupplierResponse with _$SupplierResponse {
  const factory SupplierResponse({
    int? id,
    String? name,
    String? contactType,
    String? contactValue,
  }) = _SupplierResponse;

  factory SupplierResponse.fromJson(Map<String, dynamic> json) =>
      _$SupplierResponseFromJson(json);
}

/// Podaci za kreiranje/izmjenu dobavljača (POST/PUT /api/suppliers).
@freezed
class SupplierRequest with _$SupplierRequest {
  const factory SupplierRequest({
    required String name,
    String? contactType,
    String? contactValue,
  }) = _SupplierRequest;

  factory SupplierRequest.fromJson(Map<String, dynamic> json) =>
      _$SupplierRequestFromJson(json);
}

/// Jedna stranica dobavljača (paginacija) — GET /api/suppliers.
@freezed
class PageSupplierResponse with _$PageSupplierResponse {
  const factory PageSupplierResponse({
    @Default([]) List<SupplierResponse> content,
    @Default(0) int totalPages,
    @Default(0) int totalElements,
    @Default(0) int number,
    @Default(true) bool last,
  }) = _PageSupplierResponse;

  /// Tolerantno na oblik odgovora: `content` je obično lista, ali ako backend
  /// vrati objekat (mapu), pretvorimo njegove vrijednosti u listu da parsiranje
  /// ne pukne. (Privremeno — dok ne potvrdimo tačan oblik sa backenda.)
  factory PageSupplierResponse.fromJson(Map<String, dynamic> json) {
    final content = json['content'];
    if (content is Map) {
      json = {...json, 'content': content.values.toList()};
    }
    return _$PageSupplierResponseFromJson(json);
  }
}
