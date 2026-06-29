import 'package:freezed_annotation/freezed_annotation.dart';

part 'service_models.freezed.dart';
part 'service_models.g.dart';

/// Podaci za kreiranje/izmjenu usluge (npr. šišanje, farbanje).
@freezed
class ServiceEntityRequest with _$ServiceEntityRequest {
  const factory ServiceEntityRequest({
    String? name,
    double? basicPrice,
    String? description,
  }) = _ServiceEntityRequest;

  factory ServiceEntityRequest.fromJson(Map<String, dynamic> json) =>
      _$ServiceEntityRequestFromJson(json);
}

/// Usluga kako je vraća server.
@freezed
class ServiceEntityResponse with _$ServiceEntityResponse {
  const factory ServiceEntityResponse({
    int? id,
    String? name,
    double? basicPrice,
    String? description,
  }) = _ServiceEntityResponse;

  factory ServiceEntityResponse.fromJson(Map<String, dynamic> json) =>
      _$ServiceEntityResponseFromJson(json);
}
