import 'package:freezed_annotation/freezed_annotation.dart';

part 'purchase_models.freezed.dart';
part 'purchase_models.g.dart';

/// Jedna stavka pri kreiranju nabavke (POST /api/purchases).
@freezed
class PurchaseItemRequest with _$PurchaseItemRequest {
  const factory PurchaseItemRequest({
    required int productId,
    required int quantity, // ≥ 1
    required double unitCost, // ≥ 0 (nabavna cijena po komadu, čuva se u istoriji)
  }) = _PurchaseItemRequest;

  factory PurchaseItemRequest.fromJson(Map<String, dynamic> json) =>
      _$PurchaseItemRequestFromJson(json);
}

/// Podaci za kreiranje nabavke (zaglavlje + stavke).
@freezed
class PurchaseRequest with _$PurchaseRequest {
  const factory PurchaseRequest({
    int? supplierId,
    String? note,
    required List<PurchaseItemRequest> items, // ≥ 1
  }) = _PurchaseRequest;

  factory PurchaseRequest.fromJson(Map<String, dynamic> json) =>
      _$PurchaseRequestFromJson(json);
}

/// Stavka nabavke kako je vraća server.
@freezed
class PurchaseItemResponse with _$PurchaseItemResponse {
  const factory PurchaseItemResponse({
    int? id,
    int? productId,
    String? productName,
    int? quantity,
    double? unitCost,
    double? lineTotal,
  }) = _PurchaseItemResponse;

  factory PurchaseItemResponse.fromJson(Map<String, dynamic> json) =>
      _$PurchaseItemResponseFromJson(json);
}

/// Nabavka kako je vraća server (zaglavlje + stavke).
@freezed
class PurchaseResponse with _$PurchaseResponse {
  const factory PurchaseResponse({
    int? id,
    int? supplierId,
    String? supplierName,
    int? sellingPlaceId,
    int? employeeId,
    double? totalCost,
    String? note,
    DateTime? createdAt,
    @Default([]) List<PurchaseItemResponse> items,
  }) = _PurchaseResponse;

  factory PurchaseResponse.fromJson(Map<String, dynamic> json) =>
      _$PurchaseResponseFromJson(json);
}

/// Jedna stranica nabavki (paginacija) — GET /api/purchases.
@freezed
class PagePurchaseResponse with _$PagePurchaseResponse {
  const factory PagePurchaseResponse({
    @Default([]) List<PurchaseResponse> content,
    @Default(0) int totalPages,
    @Default(0) int totalElements,
    @Default(0) int number,
    @Default(true) bool last,
  }) = _PagePurchaseResponse;

  factory PagePurchaseResponse.fromJson(Map<String, dynamic> json) =>
      _$PagePurchaseResponseFromJson(json);
}
