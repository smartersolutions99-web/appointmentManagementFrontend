import 'package:freezed_annotation/freezed_annotation.dart';

part 'shift_models.freezed.dart';
part 'shift_models.g.dart';

/// Dan u sedmici. `@JsonValue` veže Dart vrijednost za tekst sa servera
/// (npr. `WeekDay.monday` <-> "MONDAY"). Redoslijed vrijednosti je Pon→Ned,
/// pa `WeekDay.values` možemo koristiti i za prikaz u pravilnom poretku.
enum WeekDay {
  @JsonValue('MONDAY')
  monday,
  @JsonValue('TUESDAY')
  tuesday,
  @JsonValue('WEDNESDAY')
  wednesday,
  @JsonValue('THURSDAY')
  thursday,
  @JsonValue('FRIDAY')
  friday,
  @JsonValue('SATURDAY')
  saturday,
  @JsonValue('SUNDAY')
  sunday,
}

/// Nazivi dana na crnogorskom (pun i skraćeni).
extension WeekDayX on WeekDay {
  /// Pun naziv dana (npr. "Ponedjeljak").
  String get label => switch (this) {
        WeekDay.monday => 'Ponedjeljak',
        WeekDay.tuesday => 'Utorak',
        WeekDay.wednesday => 'Srijeda',
        WeekDay.thursday => 'Četvrtak',
        WeekDay.friday => 'Petak',
        WeekDay.saturday => 'Subota',
        WeekDay.sunday => 'Nedjelja',
      };

  /// Skraćeni naziv (za kompaktan prikaz, npr. "Pon").
  String get shortLabel => switch (this) {
        WeekDay.monday => 'Pon',
        WeekDay.tuesday => 'Uto',
        WeekDay.wednesday => 'Sri',
        WeekDay.thursday => 'Čet',
        WeekDay.friday => 'Pet',
        WeekDay.saturday => 'Sub',
        WeekDay.sunday => 'Ned',
      };
}

/// Jedan dan u ZAHTJEVU za šablon smjene (dan + početak/kraj rada).
/// Vrijeme se šalje kao tekst "HH:mm:ss".
@freezed
class ShiftTemplateDayRequest with _$ShiftTemplateDayRequest {
  const factory ShiftTemplateDayRequest({
    required WeekDay dayOfWeek,
    required String startTime, // "HH:mm:ss"
    required String endTime, // "HH:mm:ss"
  }) = _ShiftTemplateDayRequest;

  factory ShiftTemplateDayRequest.fromJson(Map<String, dynamic> json) =>
      _$ShiftTemplateDayRequestFromJson(json);
}

/// Zahtjev za kreiranje/izmjenu šablona smjene.
///
/// `days` U POTPUNOSTI zamjenjuje postojeće dane: dani kojih nema u listi
/// postaju „slobodan dan“ u ovom šablonu.
@freezed
class ShiftTemplateRequest with _$ShiftTemplateRequest {
  const factory ShiftTemplateRequest({
    required String name,
    String? note,
    @Default([]) List<ShiftTemplateDayRequest> days,
  }) = _ShiftTemplateRequest;

  factory ShiftTemplateRequest.fromJson(Map<String, dynamic> json) =>
      _$ShiftTemplateRequestFromJson(json);
}

/// Jedan dan u ODGOVORU (uz `id` reda).
@freezed
class ShiftTemplateDayResponse with _$ShiftTemplateDayResponse {
  const factory ShiftTemplateDayResponse({
    int? id,
    required WeekDay dayOfWeek,
    String? startTime, // "HH:mm:ss"
    String? endTime, // "HH:mm:ss"
  }) = _ShiftTemplateDayResponse;

  factory ShiftTemplateDayResponse.fromJson(Map<String, dynamic> json) =>
      _$ShiftTemplateDayResponseFromJson(json);
}

/// Šablon smjene kako ga vraća server (sa ugniježđenim danima).
@freezed
class ShiftTemplateResponse with _$ShiftTemplateResponse {
  const factory ShiftTemplateResponse({
    int? id,
    int? sellingPlaceId,
    String? name,
    String? note,
    DateTime? createdAt,
    @Default([]) List<ShiftTemplateDayResponse> days,
  }) = _ShiftTemplateResponse;

  factory ShiftTemplateResponse.fromJson(Map<String, dynamic> json) =>
      _$ShiftTemplateResponseFromJson(json);
}

/// Jedna stranica šablona smjena (paginacija) — GET /api/shift-templates.
@freezed
class PageShiftTemplateResponse with _$PageShiftTemplateResponse {
  const factory PageShiftTemplateResponse({
    @Default([]) List<ShiftTemplateResponse> content,
    @Default(0) int totalPages,
    @Default(0) int totalElements,
    @Default(0) int number,
    @Default(true) bool last,
  }) = _PageShiftTemplateResponse;

  factory PageShiftTemplateResponse.fromJson(Map<String, dynamic> json) =>
      _$PageShiftTemplateResponseFromJson(json);
}

// =============================== DODJELA SMJENA ===============================

/// Zahtjev: kojem zaposlenom dodjeljujemo koji šablon za koju sedmicu.
/// `weekStartDate` MORA biti ponedjeljak (format "YYYY-MM-DD"), inače server
/// vrati 400 NOT_A_MONDAY.
@freezed
class ShiftAssignmentRequest with _$ShiftAssignmentRequest {
  const factory ShiftAssignmentRequest({
    required int employeeId,
    required int shiftTemplateId,
    required String weekStartDate, // "YYYY-MM-DD" (ponedjeljak)
  }) = _ShiftAssignmentRequest;

  factory ShiftAssignmentRequest.fromJson(Map<String, dynamic> json) =>
      _$ShiftAssignmentRequestFromJson(json);
}

/// Dodjela smjene kako je vraća server (sa imenima zaposlenog i šablona).
@freezed
class ShiftAssignmentResponse with _$ShiftAssignmentResponse {
  const factory ShiftAssignmentResponse({
    int? id,
    int? employeeId,
    String? employeeName,
    int? shiftTemplateId,
    String? shiftTemplateName,
    String? weekStartDate, // "YYYY-MM-DD"
    DateTime? createdAt,
  }) = _ShiftAssignmentResponse;

  factory ShiftAssignmentResponse.fromJson(Map<String, dynamic> json) =>
      _$ShiftAssignmentResponseFromJson(json);
}

// =============================== RADNO VRIJEME ===============================

/// Jedan dan radnog vremena salona (ZAHTJEV) — dan + otvaranje/zatvaranje.
/// Šalje se u nizu kroz „zamjenu cijele sedmice“ (PUT /api/working-hours):
/// dani kojih nema u nizu znače da je salon tog dana zatvoren.
@freezed
class WorkingHoursRequest with _$WorkingHoursRequest {
  const factory WorkingHoursRequest({
    required WeekDay dayOfWeek,
    required String opensAt, // "HH:mm:ss"
    required String closesAt, // "HH:mm:ss"
  }) = _WorkingHoursRequest;

  factory WorkingHoursRequest.fromJson(Map<String, dynamic> json) =>
      _$WorkingHoursRequestFromJson(json);
}

/// Jedan dan radnog vremena kako ga vraća server (uz `id` i `sellingPlaceId`).
@freezed
class WorkingHoursResponse with _$WorkingHoursResponse {
  const factory WorkingHoursResponse({
    int? id,
    int? sellingPlaceId,
    required WeekDay dayOfWeek,
    String? opensAt, // "HH:mm:ss"
    String? closesAt, // "HH:mm:ss"
  }) = _WorkingHoursResponse;

  factory WorkingHoursResponse.fromJson(Map<String, dynamic> json) =>
      _$WorkingHoursResponseFromJson(json);
}

// ========================= DODJELA SMJENE PO DANU =========================

/// Zahtjev za smjenu zaposlenog za JEDAN datum (bulk upsert kroz niz).
/// Šalje se na `PUT /api/shift-days`. Vrijeme "HH:mm:ss", datum "YYYY-MM-DD".
/// `shiftTemplateId` je opcion (samo radi naziva smjene) — izostavlja se kad je null.
///
/// „Slobodan dan": kad je `off == true`, `startTime`/`endTime` se NE šalju
/// (server ih ignoriše) — taj dan zaposleni ne radi. Kad je `off` izostavljen
/// ili `false`, vremena su obavezna (`endTime > startTime`).
@freezed
class ShiftDayRequest with _$ShiftDayRequest {
  const factory ShiftDayRequest({
    required int employeeId,
    required String date, // "YYYY-MM-DD"
    @JsonKey(includeIfNull: false) String? startTime, // "HH:mm:ss" (izostavlja se za slobodan dan)
    @JsonKey(includeIfNull: false) String? endTime, // "HH:mm:ss"
    @JsonKey(includeIfNull: false) int? shiftTemplateId,
    @JsonKey(includeIfNull: false) String? note,
    @JsonKey(includeIfNull: false) bool? off, // true = slobodan dan
  }) = _ShiftDayRequest;

  factory ShiftDayRequest.fromJson(Map<String, dynamic> json) =>
      _$ShiftDayRequestFromJson(json);
}

/// Smjena zaposlenog za jedan datum kako je vraća server.
@freezed
class ShiftDayResponse with _$ShiftDayResponse {
  const factory ShiftDayResponse({
    int? id,
    int? sellingPlaceId,
    int? employeeId,
    String? employeeName,
    String? date, // "YYYY-MM-DD"
    String? startTime, // "HH:mm:ss"
    String? endTime, // "HH:mm:ss"
    int? shiftTemplateId,
    String? shiftTemplateName,
    String? note,
    @Default(false) bool off, // true = slobodan dan (zaposleni ne radi)
  }) = _ShiftDayResponse;

  factory ShiftDayResponse.fromJson(Map<String, dynamic> json) =>
      _$ShiftDayResponseFromJson(json);
}

// ===================== IZUZECI RADNOG VREMENA (PO DATUMU) =====================

/// Izuzetak radnog vremena za JEDAN datum (ZAHTJEV) — bulk upsert kroz niz.
/// Šalje se na `PUT /api/working-hours/overrides`. Ima prednost nad sedmičnim
/// šablonom za taj datum: `closed=true` → salon zatvoren; inače koristi opensAt/closesAt.
@freezed
class WorkingHoursOverrideRequest with _$WorkingHoursOverrideRequest {
  const factory WorkingHoursOverrideRequest({
    required String date, // "YYYY-MM-DD"
    required bool closed, // true = salon zatvoren tog datuma
    @JsonKey(includeIfNull: false) String? opensAt, // "HH:mm:ss" (ako radi)
    @JsonKey(includeIfNull: false) String? closesAt,
    @JsonKey(includeIfNull: false) String? note,
  }) = _WorkingHoursOverrideRequest;

  factory WorkingHoursOverrideRequest.fromJson(Map<String, dynamic> json) =>
      _$WorkingHoursOverrideRequestFromJson(json);
}

/// Izuzetak radnog vremena za jedan datum kako ga vraća server.
@freezed
class WorkingHoursOverrideResponse with _$WorkingHoursOverrideResponse {
  const factory WorkingHoursOverrideResponse({
    int? id,
    int? sellingPlaceId,
    String? date, // "YYYY-MM-DD"
    @Default(false) bool closed,
    String? opensAt, // "HH:mm:ss"
    String? closesAt,
    String? note,
  }) = _WorkingHoursOverrideResponse;

  factory WorkingHoursOverrideResponse.fromJson(Map<String, dynamic> json) =>
      _$WorkingHoursOverrideResponseFromJson(json);
}

// ============================= RASPORED (SCHEDULE) =============================

/// Raspored za jedan dan (GET /api/schedule): radno vrijeme salona + smjena
/// zaposlenog. `null` vrijednosti imaju značenje:
/// - `salonOpensAt`/`salonClosesAt` == null → salon je zatvoren tog dana;
/// - `shiftStart`/`shiftEnd` == null → zaposleni ne radi tog dana (slobodan);
/// - `shiftTemplateId` == null → nikada nije dodijeljena smjena.
///
/// (Backend NE blokira zakazivanje van smjene — ovo koristimo samo kao naznaku.)
@freezed
class ScheduleDayResponse with _$ScheduleDayResponse {
  const factory ScheduleDayResponse({
    String? date, // "YYYY-MM-DD"
    WeekDay? dayOfWeek,
    String? salonOpensAt, // "HH:mm:ss" ili null (zatvoreno)
    String? salonClosesAt,
    String? shiftStart, // "HH:mm:ss" ili null (slobodan dan)
    String? shiftEnd,
    int? shiftTemplateId, // null → smjena nikad dodijeljena
    String? shiftTemplateName,
  }) = _ScheduleDayResponse;

  factory ScheduleDayResponse.fromJson(Map<String, dynamic> json) =>
      _$ScheduleDayResponseFromJson(json);
}
