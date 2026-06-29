import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../services/providers.dart';
import '../employees/employees_provider.dart';
import '../services/services_provider.dart';

// ----- Podešavanja dnevnog rasporeda -----
const int kSlotMinutes = 15; // veličina jednog polja (slota)
const int kDayStartHour = 8; // početak radnog vremena
const int kDayEndHour = 20; // kraj radnog vremena (ekskluzivno)

/// Oznaka koju upisujemo u `note` da bismo termin označili kao pauzu.
const String kBreakNote = 'PAUZA';

/// Da li je dati termin zapravo pauza (po oznaci u napomeni).
bool isBreakNote(String? note) =>
    (note ?? '').toUpperCase().contains(kBreakNote);

/// Jedno polje (slot) u dnevnom rasporedu — interval od 30 minuta.
class ScheduleSlot {
  final DateTime start; // lokalno vrijeme početka slota
  final DateTime end; // lokalno vrijeme kraja slota
  final AppointmentResponse? appointment; // termin koji pokriva ovaj slot (ili null)
  final bool isStart; // da li termin POČINJE u ovom slotu (da ime ispišemo jednom)
  final String? customerName; // ime klijenta (ako je termin)
  final String? customerPhone; // telefon klijenta (ako je termin)

  const ScheduleSlot({
    required this.start,
    required this.end,
    this.appointment,
    this.isStart = false,
    this.customerName,
    this.customerPhone,
  });

  /// Da li je slot zauzet (ima termin koji nije otkazan).
  bool get isBusy => appointment != null;
}

/// Rezultat dnevnog rasporeda: dan, čiji je raspored i lista slotova.
class DaySchedule {
  final DateTime day; // lokalna ponoć posmatranog dana
  final int? employeeId; // čiji raspored se prikazuje
  final List<ScheduleSlot> slots;

  const DaySchedule({
    required this.day,
    required this.employeeId,
    required this.slots,
  });
}

/// Koji zaposleni se prikazuje u rasporedu. Admin ovo mijenja; za običnog
/// zaposlenog ostaje null (server svakako vraća samo njegove termine).
final scheduleEmployeeProvider = StateProvider<int?>((ref) => null);

/// Koji dan se prikazuje (lokalna ponoć tog dana). Podrazumijevano — danas.
final scheduleDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

/// Prikaz za admina: true = zbirna tabela sa svim terminima svih barbera
/// (podrazumijevano), false = raspored jednog izabranog barbera.
final scheduleShowAllProvider = StateProvider<bool>((ref) => true);

/// Detaljni zbirni prikaz: true = kolone po barberu (glavni prikaz),
/// false = kompaktni prikaz (termini dijele širinu reda).
final scheduleDetailedProvider = StateProvider<bool>((ref) => true);

/// Učitava današnji raspored: termine za dan + imena/telefone klijenata,
/// pa ih mapira u slotove od 30 minuta.
final dayScheduleProvider = FutureProvider.autoDispose<DaySchedule>((ref) async {
  final api = ref.watch(apiServiceProvider);
  final auth = ref.watch(authControllerProvider);
  final selectedEmployee = ref.watch(scheduleEmployeeProvider);

  // Admin može da bira zaposlenog (podrazumijevano svoj); običan zaposleni
  // ne šalje employeeId — server ga izvlači iz JWT tokena.
  final employeeId =
      auth.isAdmin ? (selectedEmployee ?? auth.employeeId) : null;

  // Granice izabranog dana (lokalno), poslate serveru u UTC obliku.
  final dayStart = ref.watch(scheduleDateProvider);
  final dayEnd = dayStart.add(const Duration(days: 1));

  final page = await api.getAppointments(
    from: dayStart.toUtc().toIso8601String(),
    to: dayEnd.toUtc().toIso8601String(),
    employeeId: employeeId,
    page: 0,
    size: 200,
    sort: 'startTime,asc',
  );

  // Zadržavamo samo aktivne termine. Otkazani i „nije se pojavio“ oslobađaju
  // slot, pa se može ponovo zakazati za drugog klijenta.
  final appointments = page.content
      .where((a) => a.status != AppointmentStatus.cancelled)
      .where((a) => a.status != AppointmentStatus.noShow)
      .toList();

  // Učitaj podatke o klijentima (ime + telefon) za prikaz u rasporedu.
  final customerIds =
      appointments.map((a) => a.customerId).whereType<int>().toSet();
  // Učitavamo sve klijente PARALELNO (brže nego jedan po jedan).
  final entries = await Future.wait(customerIds.map((id) async {
    try {
      return MapEntry(id, await api.getCustomer(id));
    } catch (_) {
      return null; // ako ne uspije, preskačemo
    }
  }));
  final customers = <int, CustomerResponse>{
    for (final e in entries)
      if (e != null) e.key: e.value,
  };

  // Napravi slotove od kDayStartHour do kDayEndHour, na svakih 30 min.
  final slots = <ScheduleSlot>[];
  var cursor = dayStart.add(const Duration(hours: kDayStartHour));
  final end = dayStart.add(const Duration(hours: kDayEndHour));

  while (cursor.isBefore(end)) {
    final slotStart = cursor;
    final slotEnd = cursor.add(const Duration(minutes: kSlotMinutes));

    // Nađi termin koji se preklapa sa ovim slotom.
    AppointmentResponse? covering;
    for (final a in appointments) {
      final aStart = a.startTime?.toLocal();
      final aEnd = a.endTime?.toLocal();
      if (aStart == null || aEnd == null) continue;
      // Preklapanje: termin počinje prije kraja slota i završava poslije početka.
      if (aStart.isBefore(slotEnd) && aEnd.isAfter(slotStart)) {
        covering = a;
        break;
      }
    }

    if (covering != null) {
      final aStart = covering.startTime!.toLocal();
      // „isStart“ = termin počinje unutar ovog slota (da ime ispišemo samo jednom).
      final isStart =
          !aStart.isBefore(slotStart) && aStart.isBefore(slotEnd);
      final customer = covering.customerId != null
          ? customers[covering.customerId]
          : null;
      slots.add(ScheduleSlot(
        start: slotStart,
        end: slotEnd,
        appointment: covering,
        isStart: isStart,
        // Prvo sa termina (radi i za barbere), pa tek onda iz getCustomer.
        customerName: covering.customerName ?? customer?.name,
        customerPhone: covering.customerPhone ?? customer?.contactValue,
      ));
    } else {
      slots.add(ScheduleSlot(start: slotStart, end: slotEnd));
    }

    cursor = slotEnd;
  }

  return DaySchedule(day: dayStart, employeeId: employeeId, slots: slots);
});

// ===================== AGENDA: SVI BARBERI (admin) =====================

/// Jedna stavka u agendi: termin + ime barbera + ime/telefon klijenta.
class AgendaItem {
  final AppointmentResponse appointment;
  final int? employeeId; // barber
  final String? barberName;
  final String? customerName;
  final String? customerPhone;

  const AgendaItem({
    required this.appointment,
    required this.employeeId,
    required this.barberName,
    required this.customerName,
    required this.customerPhone,
  });

  DateTime get start => appointment.startTime!.toLocal();
  DateTime? get end => appointment.endTime?.toLocal();
}

/// Jedan termin prikazan kao linija u zbirnoj tabeli (svi barberi):
/// barber + klijent + telefon + usluga.
class SlotEntry {
  final int? employeeId;
  final String? barberName;
  final String? customerName;
  final String? customerPhone;
  final String? serviceName;
  final bool isStart; // da li termin POČINJE baš u ovom slotu (tekst se ispisuje
  // samo jednom, dok ostali pokriveni slotovi budu samo obojeni)
  final bool isBreak; // da li je ovo pauza (a ne termin sa klijentom)

  const SlotEntry({
    required this.employeeId,
    required this.barberName,
    required this.customerName,
    required this.customerPhone,
    required this.serviceName,
    required this.isStart,
    required this.isBreak,
  });
}

/// Jedan slot (15 min) u zbirnoj tabeli: vrijeme + svi termini koji tu počinju.
class AllSlot {
  final DateTime start;
  final DateTime end;
  final List<SlotEntry> entries; // svi barberi koji počinju u ovom slotu

  const AllSlot({required this.start, required this.end, required this.entries});
}

/// Zbirni dnevni raspored svih barbera (za admin „Sve“ prikaz).
class AllDaySchedule {
  final DateTime day;
  final List<AllSlot> slots;
  final Map<int, String?> barbers; // barberi sa terminima (za legendu)

  const AllDaySchedule({
    required this.day,
    required this.slots,
    required this.barbers,
  });
}

/// Pravi zbirnu tabelu svih barbera za izabrani dan. Ista vremenska mreža kao
/// kod jednog barbera (08–20h, 15 min), ali svaki slot može imati više linija
/// (po jednu za svakog barbera čiji termin tu počinje).
final allDayScheduleProvider =
    FutureProvider.autoDispose<AllDaySchedule>((ref) async {
  final api = ref.watch(apiServiceProvider);
  final dayStart = ref.watch(scheduleDateProvider);
  final dayEnd = dayStart.add(const Duration(days: 1));

  // Bez employeeId filtera → server vraća sve termine (admin to smije).
  final page = await api.getAppointments(
    from: dayStart.toUtc().toIso8601String(),
    to: dayEnd.toUtc().toIso8601String(),
    page: 0,
    size: 200,
    sort: 'startTime,asc',
  );

  // Otkazani i „nije se pojavio“ oslobađaju slot (ne prikazujemo ih).
  final appointments = page.content
      .where((a) => a.status != AppointmentStatus.cancelled)
      .where((a) => a.status != AppointmentStatus.noShow)
      .where((a) => a.startTime != null)
      .toList();

  // Imena barbera (employeeId → ime).
  final employees = await ref.watch(employeesProvider.future);
  final barberById = {for (final e in employees) e.id: e.name};

  // Usluge (serviceId → ime). Ako ne uspije, samo izostavimo naziv usluge.
  List<ServiceEntityResponse> services;
  try {
    services = await ref.watch(servicesProvider.future);
  } catch (_) {
    services = const [];
  }
  final serviceById = {for (final s in services) s.id: s.name};

  // Podaci o klijentima (paralelno).
  final customerIds =
      appointments.map((a) => a.customerId).whereType<int>().toSet();
  final entries = await Future.wait(customerIds.map((id) async {
    try {
      return MapEntry(id, await api.getCustomer(id));
    } catch (_) {
      return null;
    }
  }));
  final customers = <int, CustomerResponse>{
    for (final e in entries)
      if (e != null) e.key: e.value,
  };

  // Vremenska mreža 08:00–20:00 na 15 minuta.
  final slots = <AllSlot>[];
  var cursor = dayStart.add(const Duration(hours: kDayStartHour));
  final end = dayStart.add(const Duration(hours: kDayEndHour));
  while (cursor.isBefore(end)) {
    final slotStart = cursor;
    final slotEnd = cursor.add(const Duration(minutes: kSlotMinutes));

    // Termini koji POKRIVAJU ovaj slot (bilo koji barber) — i početni i oni
    // koji se nastavljaju iz prethodnog slota (npr. 8:30–9:00 puni 8:30 i 8:45).
    final slotEntries = <SlotEntry>[];
    for (final a in appointments) {
      final aStart = a.startTime!.toLocal();
      // Kraj termina: iz endTime, ili izračunat iz trajanja, ili 1 slot.
      final aEnd = a.endTime?.toLocal() ??
          aStart.add(Duration(minutes: a.duration ?? kSlotMinutes));
      // Preklapanje: počinje prije kraja slota i završava poslije početka slota.
      if (aStart.isBefore(slotEnd) && aEnd.isAfter(slotStart)) {
        final isStart =
            !aStart.isBefore(slotStart) && aStart.isBefore(slotEnd);
        final cust = a.customerId != null ? customers[a.customerId] : null;
        slotEntries.add(SlotEntry(
          employeeId: a.employeeId,
          barberName: barberById[a.employeeId],
          customerName: a.customerName ?? cust?.name,
          customerPhone: a.customerPhone ?? cust?.contactValue,
          serviceName: serviceById[a.serviceId],
          isStart: isStart,
          isBreak: isBreakNote(a.note),
        ));
      }
    }
    // Poređaj linije po imenu barbera (stabilan prikaz).
    slotEntries.sort((x, y) => (x.barberName ?? '').compareTo(y.barberName ?? ''));

    slots.add(AllSlot(start: slotStart, end: slotEnd, entries: slotEntries));
    cursor = slotEnd;
  }

  // Legenda: SVI zaposleni (ne samo oni koji danas imaju termine).
  final barbers = <int, String?>{
    for (final e in employees)
      if (e.id != null) e.id!: e.name,
  };

  return AllDaySchedule(day: dayStart, slots: slots, barbers: barbers);
});

// ===================== PRETRAGA TERMINA PO KLIJENTU =====================

/// Pretraga termina po imenu klijenta ili broju telefona.
///
/// Server nema direktan filter po klijentu, pa učitamo termine u prozoru od
/// danas do +90 dana, spojimo podatke o klijentima i barberima, pa filtriramo
/// lokalno po unesenom tekstu. Vraća pogođene termine poređane po vremenu.
final appointmentSearchProvider =
    FutureProvider.autoDispose.family<List<AgendaItem>, String>((ref, query) async {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];

  final api = ref.watch(apiServiceProvider);
  final now = DateTime.now();
  final from = DateTime(now.year, now.month, now.day);
  final to = from.add(const Duration(days: 90));

  final page = await api.getAppointments(
    from: from.toUtc().toIso8601String(),
    to: to.toUtc().toIso8601String(),
    page: 0,
    size: 500,
    sort: 'startTime,asc',
  );

  final appointments = page.content
      .where((a) => a.status != AppointmentStatus.cancelled)
      .where((a) => a.startTime != null)
      .toList();

  final employees = await ref.watch(employeesProvider.future);
  final barberById = {for (final e in employees) e.id: e.name};

  final customerIds =
      appointments.map((a) => a.customerId).whereType<int>().toSet();
  final entries = await Future.wait(customerIds.map((id) async {
    try {
      return MapEntry(id, await api.getCustomer(id));
    } catch (_) {
      return null;
    }
  }));
  final customers = <int, CustomerResponse>{
    for (final e in entries)
      if (e != null) e.key: e.value,
  };

  final items = [
    for (final a in appointments)
      AgendaItem(
        appointment: a,
        employeeId: a.employeeId,
        barberName: barberById[a.employeeId],
        customerName: a.customerName ??
            (a.customerId != null ? customers[a.customerId]?.name : null),
        customerPhone: a.customerPhone ??
            (a.customerId != null
                ? customers[a.customerId]?.contactValue
                : null),
      ),
  ];

  // Filtriraj po imenu ILI telefonu (mala/velika slova nisu bitna).
  return items.where((it) {
    final name = (it.customerName ?? '').toLowerCase();
    final phone = (it.customerPhone ?? '').toLowerCase();
    return name.contains(q) || phone.contains(q);
  }).toList();
});
