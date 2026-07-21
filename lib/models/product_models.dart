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

/// Proizvod kako ga vraća server (uključuje trenutnu zalihu i naziv dobavljača).
@freezed
class ProductResponse with _$ProductResponse {
  const factory ProductResponse({
    int? id,
    String? name,
    double? price,
    double? finalPrice,
    int? supplierId,
    String? supplierName,
    String? description,
    int? sellingPlaceId,
    int? quantity, // trenutna zaliha (mijenja se samo kroz nabavke/prodaje)
  }) = _ProductResponse;

  factory ProductResponse.fromJson(Map<String, dynamic> json) =>
      _$ProductResponseFromJson(json);
}

/// Jedna stranica proizvoda (paginacija) — GET /api/products.
@freezed
class PageProductResponse with _$PageProductResponse {
  const factory PageProductResponse({
    @Default([]) List<ProductResponse> content,
    @Default(0) int totalPages,
    @Default(0) int totalElements,
    @Default(0) int number,
    @Default(true) bool last,
  }) = _PageProductResponse;

  factory PageProductResponse.fromJson(Map<String, dynamic> json) =>
      _$PageProductResponseFromJson(json);
}

/// Stavka sa malom zalihom — GET /api/products/low-stock.
@freezed
class LowStockItem with _$LowStockItem {
  const factory LowStockItem({
    int? productId,
    String? name,
    int? quantity,
    int? supplierId,
    String? supplierName,
  }) = _LowStockItem;

  factory LowStockItem.fromJson(Map<String, dynamic> json) =>
      _$LowStockItemFromJson(json);
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

  factory PageSupplierResponse.fromJson(Map<String, dynamic> json) =>
      _$PageSupplierResponseFromJson(json);
}
