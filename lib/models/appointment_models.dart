import 'package:freezed_annotation/freezed_annotation.dart';

part 'appointment_models.freezed.dart';
part 'appointment_models.g.dart';

/// Status termina. `@JsonValue` veže Dart vrijednost za tekst sa servera.
enum AppointmentStatus {
  @JsonValue('SCHEDULED')
  scheduled,
  @JsonValue('COMPLETED')
  completed,
  @JsonValue('CANCELLED')
  cancelled,
  @JsonValue('NO_SHOW')
  noShow,
}

/// Pomoćne metode za status (naziv na crnogorskom i tekst za server).
extension AppointmentStatusX on AppointmentStatus {
  /// Naziv koji prikazujemo korisniku.
  String get label => switch (this) {
        AppointmentStatus.scheduled => 'Zakazan',
        AppointmentStatus.completed => 'Završen',
        AppointmentStatus.cancelled => 'Otkazan',
        AppointmentStatus.noShow => 'Nije se pojavio',
      };

  /// Vrijednost koju očekuje server (npr. za filter ili promjenu statusa).
  String get apiValue => switch (this) {
        AppointmentStatus.scheduled => 'SCHEDULED',
        AppointmentStatus.completed => 'COMPLETED',
        AppointmentStatus.cancelled => 'CANCELLED',
        AppointmentStatus.noShow => 'NO_SHOW',
      };
}

/// Podaci za kreiranje/izmjenu termina.
@freezed
class AppointmentRequest with _$AppointmentRequest {
  const factory AppointmentRequest({
    int? customerId,
    String? customerPhone,
    String? customerName,
    int? employeeId,
    int? serviceId,
    required DateTime startTime,
    required int duration, // trajanje u minutima
    required double servicePrice,
    String? note,
    String? contactType,
  }) = _AppointmentRequest;

  factory AppointmentRequest.fromJson(Map<String, dynamic> json) =>
      _$AppointmentRequestFromJson(json);
}

/// Termin kako ga vraća server.
@freezed
class AppointmentResponse with _$AppointmentResponse {
  const factory AppointmentResponse({
    int? id,
    int? customerId,
    // Neki serveri vraćaju ime/telefon klijenta direktno na terminu — koristimo
    // ih kad postoje (pa ne moramo zvati getCustomer, koji barberima vraća 403).
    String? customerName,
    String? customerPhone,
    int? serviceId,
    int? employeeId,
    int? duration,
    DateTime? startTime,
    DateTime? endTime,
    AppointmentStatus? status,
    String? note,
    double? servicePrice,
    String? contactType,
    int? storedById,
  }) = _AppointmentResponse;

  factory AppointmentResponse.fromJson(Map<String, dynamic> json) =>
      _$AppointmentResponseFromJson(json);
}

/// Zahtjev za promjenu statusa termina (PATCH /api/appointments/{id}/status).
@freezed
class StatusChangeRequest with _$StatusChangeRequest {
  const factory StatusChangeRequest({
    required AppointmentStatus status,
  }) = _StatusChangeRequest;

  factory StatusChangeRequest.fromJson(Map<String, dynamic> json) =>
      _$StatusChangeRequestFromJson(json);
}

/// Jedna stranica termina (paginacija).
@freezed
class PageAppointmentResponse with _$PageAppointmentResponse {
  const factory PageAppointmentResponse({
    @Default([]) List<AppointmentResponse> content,
    @Default(0) int totalPages,
    @Default(0) int totalElements,
    @Default(0) int number,
    @Default(true) bool last,
  }) = _PageAppointmentResponse;

  factory PageAppointmentResponse.fromJson(Map<String, dynamic> json) =>
      _$PageAppointmentResponseFromJson(json);
}
