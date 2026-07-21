import 'package:freezed_annotation/freezed_annotation.dart';

part 'sale_models.freezed.dart';
part 'sale_models.g.dart';

/// Jedna stavka pri kreiranju prodaje (POST /api/sales).
///
/// `unitPrice` je opcionalno: ako ga izostavimo, server uzima prodajnu cijenu
/// proizvoda (`finalPrice`). Ako ga pošaljemo, to je „override“ (npr. popust).
/// Zato koristimo `includeIfNull: false` — kad je `null`, polje se NE šalje.
@freezed
class SaleItemRequest with _$SaleItemRequest {
  const factory SaleItemRequest({
    required int productId,
    required int quantity, // ≥ 1
    @JsonKey(includeIfNull: false) double? unitPrice,
  }) = _SaleItemRequest;

  factory SaleItemRequest.fromJson(Map<String, dynamic> json) =>
      _$SaleItemRequestFromJson(json);
}

/// Podaci za kreiranje prodaje (zaglavlje + stavke).
@freezed
class SaleRequest with _$SaleRequest {
  const factory SaleRequest({
    @Default(false) bool isInternal, // true = barber uzeo za ličnu upotrebu
    @JsonKey(includeIfNull: false) String? note,
    required List<SaleItemRequest> items, // ≥ 1
  }) = _SaleRequest;

  factory SaleRequest.fromJson(Map<String, dynamic> json) =>
      _$SaleRequestFromJson(json);
}

/// Stavka prodaje kako je vraća server.
@freezed
class SaleItemResponse with _$SaleItemResponse {
  const factory SaleItemResponse({
    int? id,
    int? productId,
    String? productName,
    int? quantity,
    double? unitPrice,
    double? lineTotal,
  }) = _SaleItemResponse;

  factory SaleItemResponse.fromJson(Map<String, dynamic> json) =>
      _$SaleItemResponseFromJson(json);
}

/// Prodaja kako je vraća server (zaglavlje + stavke).
@freezed
class SaleResponse with _$SaleResponse {
  const factory SaleResponse({
    int? id,
    int? sellingPlaceId,
    int? employeeId,
    double? total,
    @Default(false) bool isInternal,
    String? note,
    DateTime? createdAt,
    @Default([]) List<SaleItemResponse> items,
  }) = _SaleResponse;

  factory SaleResponse.fromJson(Map<String, dynamic> json) =>
      _$SaleResponseFromJson(json);
}

/// Jedna stranica prodaja (paginacija) — GET /api/sales.
@freezed
class PageSaleResponse with _$PageSaleResponse {
  const factory PageSaleResponse({
    @Default([]) List<SaleResponse> content,
    @Default(0) int totalPages,
    @Default(0) int totalElements,
    @Default(0) int number,
    @Default(true) bool last,
  }) = _PageSaleResponse;

  factory PageSaleResponse.fromJson(Map<String, dynamic> json) =>
      _$PageSaleResponseFromJson(json);
}
