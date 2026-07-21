import 'package:freezed_annotation/freezed_annotation.dart';

part 'employee_models.freezed.dart';
part 'employee_models.g.dart';

/// Podaci za kreiranje/izmjenu zaposlenog.
@freezed
class EmployeeRequest with _$EmployeeRequest {
  const factory EmployeeRequest({
    String? name,
    String? username,
    String? password,
    int? roleId,
    int? sellingPlaceId,
    double? rating,
    String? phoneNumber,
    String? email,
    int? defaultAppointmentDuration, // podrazumijevano trajanje termina (min)
  }) = _EmployeeRequest;

  factory EmployeeRequest.fromJson(Map<String, dynamic> json) =>
      _$EmployeeRequestFromJson(json);
}

/// Zaposleni kako ga vraća server.
@freezed
class EmployeeResponse with _$EmployeeResponse {
  const factory EmployeeResponse({
    int? id,
    String? name,
    String? username,
    int? roleId,
    int? sellingPlaceId,
    double? rating,
    String? phoneNumber,
    String? email,
    int? defaultAppointmentDuration, // podrazumijevano trajanje termina (min)
    DateTime? createdAt,
    DateTime? updatedAt,
  }) = _EmployeeResponse;

  factory EmployeeResponse.fromJson(Map<String, dynamic> json) =>
      _$EmployeeResponseFromJson(json);
}

/// Uloga (rola) — koristi se za padajuće liste pri unosu zaposlenog.
@freezed
class RoleResponse with _$RoleResponse {
  const factory RoleResponse({
    int? id,
    String? naziv, // naziv uloge (server koristi crnogorske nazive polja)
    String? opis,
  }) = _RoleResponse;

  factory RoleResponse.fromJson(Map<String, dynamic> json) =>
      _$RoleResponseFromJson(json);
}

/// Prodajno mjesto (lokacija salona).
@freezed
class SellingPlaceResponse with _$SellingPlaceResponse {
  const factory SellingPlaceResponse({
    int? id,
    String? name,
    String? address,
  }) = _SellingPlaceResponse;

  factory SellingPlaceResponse.fromJson(Map<String, dynamic> json) =>
      _$SellingPlaceResponseFromJson(json);
}
