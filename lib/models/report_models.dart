import 'package:freezed_annotation/freezed_annotation.dart';

part 'report_models.freezed.dart';
part 'report_models.g.dart';

/// Sažetak prihoda za period (ukupan prihod + broj završenih termina).
@freezed
class RevenueSummary with _$RevenueSummary {
  const factory RevenueSummary({
    @Default(0) double totalRevenue,
    @Default(0) int completedAppointments,
  }) = _RevenueSummary;

  factory RevenueSummary.fromJson(Map<String, dynamic> json) =>
      _$RevenueSummaryFromJson(json);
}

/// Prihod po zaposlenom (za rang listu „top zaposleni“).
@freezed
class EmployeeRevenue with _$EmployeeRevenue {
  const factory EmployeeRevenue({
    int? employeeId,
    String? employeeName,
    @Default(0) double totalRevenue,
    @Default(0) int completedAppointments,
  }) = _EmployeeRevenue;

  factory EmployeeRevenue.fromJson(Map<String, dynamic> json) =>
      _$EmployeeRevenueFromJson(json);
}

/// Prihod po vremenskom intervalu (za grafikon kroz vrijeme).
@freezed
class RevenueBucket with _$RevenueBucket {
  const factory RevenueBucket({
    DateTime? bucketStart,
    @Default(0) double revenue,
    @Default(0) int completedAppointments,
  }) = _RevenueBucket;

  factory RevenueBucket.fromJson(Map<String, dynamic> json) =>
      _$RevenueBucketFromJson(json);
}
