import 'package:freezed_annotation/freezed_annotation.dart';

part 'tip_models.freezed.dart';
part 'tip_models.g.dart';

/// Unos DNEVNOG ukupnog bakšiša (PUT /api/tips/daily) — upsert po zaposlenom+datumu.
@freezed
class TipDailyRequest with _$TipDailyRequest {
  const factory TipDailyRequest({
    required int employeeId,
    required String date, // "YYYY-MM-DD"
    required double amount, // ≥ 0
    @JsonKey(includeIfNull: false) String? note,
  }) = _TipDailyRequest;

  factory TipDailyRequest.fromJson(Map<String, dynamic> json) =>
      _$TipDailyRequestFromJson(json);
}

/// Unos bakšiša za KONKRETAN termin (PUT /api/tips/appointment/{appointmentId}).
/// Zaposleni i datum se izvode iz termina na serveru.
@freezed
class TipAppointmentRequest with _$TipAppointmentRequest {
  const factory TipAppointmentRequest({
    required double amount, // ≥ 0
    @JsonKey(includeIfNull: false) String? note,
  }) = _TipAppointmentRequest;

  factory TipAppointmentRequest.fromJson(Map<String, dynamic> json) =>
      _$TipAppointmentRequestFromJson(json);
}

/// Bakšiš kako ga vraća server.
@freezed
class TipResponse with _$TipResponse {
  const factory TipResponse({
    int? id,
    int? employeeId,
    String? employeeName,
    int? appointmentId, // null za dnevni ukupni, postavljen za bakšiš po terminu
    String? date, // "YYYY-MM-DD"
    double? amount,
    String? note,
    DateTime? createdAt,
  }) = _TipResponse;

  factory TipResponse.fromJson(Map<String, dynamic> json) =>
      _$TipResponseFromJson(json);
}

/// Zbir bakšiša po zaposlenom (GET /api/tips/summary).
@freezed
class TipSummary with _$TipSummary {
  const factory TipSummary({
    int? employeeId,
    String? employeeName,
    @Default(0) double totalTips,
  }) = _TipSummary;

  factory TipSummary.fromJson(Map<String, dynamic> json) =>
      _$TipSummaryFromJson(json);
}

/// Jedan ukupan zbir bakšiša za period (GET /api/tips/total).
@freezed
class TipTotal with _$TipTotal {
  const factory TipTotal({
    String? from,
    String? to,
    @Default(0) double total,
  }) = _TipTotal;

  factory TipTotal.fromJson(Map<String, dynamic> json) =>
      _$TipTotalFromJson(json);
}
