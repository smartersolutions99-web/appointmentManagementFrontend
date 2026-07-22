import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../services/providers.dart';
import '../employees/employees_provider.dart';
import '../services/services_provider.dart';

// ----- Podešavanja dnevnog rasporeda -----
const int kSlotMinutes = 15; // veličina jednog polja (slota)

// ----- Zoom rasporeda (Excel-stil) -----
// Množilac kojim skaliramo visine redova i veličine fonta u rasporedu.
// 1.0 = podrazumijevano (u „Pregled" prikazu tada cijeli dan stane na ekran).
// Vrijednost > 1 uvećava ćelije (pa se skroluje), < 1 ih smanjuje.
const double kMinZoom = 0.5;
const double kMaxZoom = 3.0;
const double kZoomStep = 0.1; // korak za dugmad i tastaturu (Ctrl +/−)

// Podrazumijevani okvir mreže (08:00–21:00). Koristi se kad ne znamo radno
// vrijeme/smjenu — npr. za PROŠLE dane, gdje namjerno prikazujemo širok raspon
// jer se radno vrijeme moglo mijenjati u međuvremenu.
const int _defaultStartMin = 8 * 60; // 08:00
const int _defaultEndMin = 21 * 60; // 21:00

/// Oznaka koju upisujemo u `note` da bismo termin označili kao pauzu.
const String kBreakNote = 'PAUZA';

/// Da li je dati termin zapravo pauza (po oznaci u napomeni).
bool isBreakNote(String? note) =>
    (note ?? '').toUpperCase().contains(kBreakNote);

/// "YYYY-MM-DD" za dati (lokalni) dan — format koji server očekuje.
String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Minuti od ponoći iz "HH:mm:ss" (ili null ako fali/neispravno).
int? _minutesOfDay(String? hhmmss) {
  if (hhmmss == null) return null;
  final p = hhmmss.split(':');
  if (p.length < 2) return null;
  final h = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

/// Izračunaj vremenski okvir (start–end) mreže za dati dan.
///
/// [primaryStartMin]/[primaryEndMin] je željeni okvir (smjena barbera ili radno
/// vrijeme salona) u minutima od ponoći; ako nije poznat, koristi se
/// podrazumijevani (08–21). Okvir se UVIJEK proširi da pokrije sve postojeće
/// termine — da se nijedan termin slučajno ne bi sakrio.
({DateTime start, DateTime end}) _dayWindow(
  DateTime dayStart,
  int? primaryStartMin,
  int? primaryEndMin,
  List<AppointmentResponse> appts, {
  int step = kSlotMinutes, // veličina slota (za poravnanje okvira)
}) {
  int startMin;
  int endMin;
  if (primaryStartMin != null &&
      primaryEndMin != null &&
      primaryEndMin > primaryStartMin) {
    startMin = primaryStartMin;
    endMin = primaryEndMin;
  } else {
    startMin = _defaultStartMin;
    endMin = _defaultEndMin;
  }

  for (final a in appts) {
    final s = a.startTime?.toLocal();
    if (s != null) {
      final sm = s.hour * 60 + s.minute;
      final floor = sm - (sm % step); // zaokruži naniže na slot
      if (floor < startMin) startMin = floor;
    }
    final e = a.endTime?.toLocal() ??
        s?.add(Duration(minutes: a.duration ?? step));
    if (e != null) {
      // Ako termin pređe ponoć, računamo do kraja dana (24:00).
      final em = (e.year == dayStart.year &&
              e.month == dayStart.month &&
              e.day == dayStart.day)
          ? e.hour * 60 + e.minute
          : 24 * 60;
      final ceil = ((em + step - 1) ~/ step) * step;
      if (ceil > endMin) endMin = ceil;
    }
  }

  startMin = startMin.clamp(0, 24 * 60).toInt();
  endMin = endMin.clamp(0, 24 * 60).toInt();
  if (endMin <= startMin) {
    endMin = (startMin + step).clamp(0, 24 * 60).toInt();
  }

  return (
    start: dayStart.add(Duration(minutes: startMin)),
    end: dayStart.add(Duration(minutes: endMin)),
  );
}

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

/// Rezultat dnevnog rasporeda: dan, čiji je raspored, lista slotova i zbir dana.
class DaySchedule {
  final DateTime day; // lokalna ponoć posmatranog dana
  final int? employeeId; // čiji raspored se prikazuje
  final List<ScheduleSlot> slots;
  final int appointmentCount; // broj termina tog dana (bez pauza)
  final int completedCount; // broj završenih termina (bez pauza)
  final double earned; // zbir cijena ZAVRŠENIH termina (bez pauza)
  final int slotMinutes; // veličina slota (trajanje termina barbera; default 15)

  const DaySchedule({
    required this.day,
    required this.employeeId,
    required this.slots,
    this.appointmentCount = 0,
    this.completedCount = 0,
    this.earned = 0,
    this.slotMinutes = kSlotMinutes,
  });
}

/// Adresar svih klijenata (ime + telefon + id) — za „našaptavanje" u formama
/// zakazivanja. Učitava se jednom i filtrira LOKALNO, pa i pretraga po imenu i
/// pretraga po telefonu rade isto i reaguju trenutno (bez poziva servera na
/// svaki pritisak tastera). Učitavamo do nekoliko stranica, uz sigurnosnu granicu.
final customerDirectoryProvider =
    FutureProvider.autoDispose<List<CustomerResponse>>((ref) async {
  final api = ref.watch(apiServiceProvider);
  final all = <CustomerResponse>[];
  var page = 0;
  while (true) {
    final res = await api.getCustomers(page: page, size: 200, sort: 'name,asc');
    all.addAll(res.content);
    // Stani na posljednjoj stranici ili nakon 20 stranica (sigurnosna granica).
    if (res.last || page >= 20) break;
    page++;
  }
  return all;
});

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

/// Način zbirnog prikaza (kad admin gleda „Svi barberi"):
/// - [grid]    — detaljna mreža: kolone po barberu, mreža po vremenu;
/// - [list]    — kompaktna lista: svi termini u redu, dijele širinu;
/// - [overview]— pregled: kolone po barberu, SAMO termini (bez praznih polja),
///   pa cijeli dan stane na ekran bez skrolanja (glavni, podrazumijevani prikaz).
enum AllScheduleView { grid, list, overview }

/// Izabrani način zbirnog prikaza. Podrazumijevano „Pregled" — jer admin tu
/// najčešće radi (cijeli dan stane na ekran bez skrolanja).
final scheduleViewProvider =
    StateProvider<AllScheduleView>((ref) => AllScheduleView.overview);

/// Zoom nivo rasporeda (Excel-stil). Čuvamo ga u provideru da ostane zapamćen
/// dok se krećemo po danima/prikazima i pri ulasku u puni ekran. Vidi [kMinZoom]/
/// [kMaxZoom]/[kZoomStep] i kako se primjenjuje u `day_schedule_view.dart`.
final scheduleZoomProvider = StateProvider<double>((ref) => 1.0);

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

  // Zbir dana (za footer): brojimo termine (bez pauza) i sabiramo cijene
  // ZAVRŠENIH termina. Pauze nemaju klijenta ni cijenu, pa ih izostavljamo.
  final realAppointments =
      appointments.where((a) => !isBreakNote(a.note)).toList();
  final completed = realAppointments
      .where((a) => a.status == AppointmentStatus.completed)
      .toList();
  final appointmentCount = realAppointments.length;
  final completedCount = completed.length;
  final earned =
      completed.fold<double>(0, (sum, a) => sum + (a.servicePrice ?? 0));

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

  // Okvir mreže = SMJENA barbera za ovaj dan (za današnji i buduće dane); za
  // prošle dane ili kad smjena nije poznata → podrazumijevani okvir (08–21).
  // Raspored dohvatamo preko dayScheduleInfoProvider (isti poziv kao za banner),
  // a grešku tiho progutamo da ne sruši glavni prikaz.
  ScheduleDayResponse? sched;
  try {
    sched = await ref.watch(dayScheduleInfoProvider.future);
  } catch (_) {
    sched = null;
  }
  final now = DateTime.now();
  final isPast = dayStart.isBefore(DateTime(now.year, now.month, now.day));
  int? primaryStart;
  int? primaryEnd;
  if (!isPast && sched != null) {
    if (auth.isAdmin) {
      // Admin (gleda barbera): prvo smjena barbera; ako je nema, radno vrijeme
      // salona kao rezerva.
      primaryStart =
          _minutesOfDay(sched.shiftStart) ?? _minutesOfDay(sched.salonOpensAt);
      primaryEnd =
          _minutesOfDay(sched.shiftEnd) ?? _minutesOfDay(sched.salonClosesAt);
    } else {
      // Običan zaposleni: prikazujemo ISKLJUČIVO satnicu njegove smjene (bez
      // radnog vremena salona). Ako smjena nije dodijeljena, ostaje bez okvira
      // (mreža se svede na eventualne postojeće termine tog dana).
      primaryStart = _minutesOfDay(sched.shiftStart);
      primaryEnd = _minutesOfDay(sched.shiftEnd);
    }
  }
  // Veličina slota = defaultAppointmentDuration barbera (ako je poznato), inače
  // 15 min. Ovaj podatak čitamo iz liste zaposlenih, koja je admin-only — pa
  // običan zaposleni koji gleda svoj raspored dobija podrazumijevanih 15 min.
  var slotSize = kSlotMinutes;
  if (auth.isAdmin && employeeId != null) {
    try {
      final employees = await ref.watch(employeesProvider.future);
      for (final e in employees) {
        if (e.id == employeeId) {
          final d = e.defaultAppointmentDuration;
          if (d != null && d > 0) slotSize = d;
          break;
        }
      }
    } catch (_) {
      // Ignorišemo — ostaje podrazumijevanih 15 min.
    }
  }

  final window = _dayWindow(dayStart, primaryStart, primaryEnd, appointments,
      step: slotSize);

  // Napravi slotove kroz izračunati okvir, na svakih `slotSize` minuta.
  final slots = <ScheduleSlot>[];
  var cursor = window.start;
  final end = window.end;

  while (cursor.isBefore(end)) {
    final slotStart = cursor;
    final slotEnd = cursor.add(Duration(minutes: slotSize));

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

  return DaySchedule(
    day: dayStart,
    employeeId: employeeId,
    slots: slots,
    appointmentCount: appointmentCount,
    completedCount: completedCount,
    earned: earned,
    slotMinutes: slotSize,
  );
});

/// Raspored (radno vrijeme salona + smjena) za IZABRANI dan i barbera —
/// koristi se kao vizuelna naznaka iznad rasporeda jednog barbera.
///
/// Namjerno NE hvatamo grešku ovdje: UI čita `.valueOrNull`, pa ako endpoint
/// zakaže (ili još nije objavljen na serveru), naznaka se jednostavno ne
/// prikaže — kalendar i dalje radi normalno.
final dayScheduleInfoProvider =
    FutureProvider.autoDispose<ScheduleDayResponse?>((ref) async {
  final api = ref.watch(apiServiceProvider);
  final auth = ref.watch(authControllerProvider);
  final selectedEmployee = ref.watch(scheduleEmployeeProvider);

  // Isti izbor barbera kao u dayScheduleProvider: admin bira (podrazumijevano
  // svoj), običan zaposleni ne šalje employeeId (server ga uzme iz tokena).
  final employeeId =
      auth.isAdmin ? (selectedEmployee ?? auth.employeeId) : null;

  final day = ref.watch(scheduleDateProvider);
  final ymd = '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  final list =
      await api.getSchedule(employeeId: employeeId, from: ymd, to: ymd);
  return list.isNotEmpty ? list.first : null;
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
  final double? servicePrice; // cijena usluge (prikazuje se uz ime i telefon)
  final DateTime? startTime; // početak termina (za prikaz „od–do")
  final DateTime? endTime; // kraj termina (za prikaz „od–do")
  final AppointmentResponse appointment; // pun termin (za tap → promjena statusa)
  final bool isStart; // da li termin POČINJE baš u ovom slotu (tekst se ispisuje
  // samo jednom, dok ostali pokriveni slotovi budu samo obojeni)
  final bool isBreak; // da li je ovo pauza (a ne termin sa klijentom)

  const SlotEntry({
    required this.employeeId,
    required this.barberName,
    required this.customerName,
    required this.customerPhone,
    required this.serviceName,
    required this.servicePrice,
    required this.startTime,
    required this.endTime,
    required this.appointment,
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

/// Jedan slot u koloni JEDNOG barbera („Pregled"), veličine NJEGOVOG trajanja
/// (defaultAppointmentDuration). Za razliku od `AllSlot` (zajednička 15-min
/// mreža za Mrežu/Listu), ovdje svaki barber ima svoju veličinu slota.
class BoardSlot {
  final DateTime start;
  final DateTime end;
  final SlotEntry? entry; // termin koji pokriva ovaj slot (ili null)

  const BoardSlot({required this.start, required this.end, this.entry});

  bool get isBusy => entry != null;
}

/// Zbir dana za jednog barbera (za footer u „Pregled" prikazu).
class BarberDayTotals {
  final int appointmentCount; // broj termina (bez pauza)
  final int completedCount; // broj završenih
  final double earned; // zbir cijena ZAVRŠENIH termina

  const BarberDayTotals({
    this.appointmentCount = 0,
    this.completedCount = 0,
    this.earned = 0,
  });
}

/// Zbirni dnevni raspored svih barbera (za admin „Sve“ prikaz).
class AllDaySchedule {
  final DateTime day;
  final List<AllSlot> slots;
  final Map<int, String?> barbers; // barberi sa terminima (za legendu)
  final Map<int, BarberDayTotals> totalsByBarber; // zbir dana po barberu
  final Map<int, List<BoardSlot>> boardColumns; // po barberu (za „Pregled")

  const AllDaySchedule({
    required this.day,
    required this.slots,
    required this.barbers,
    this.totalsByBarber = const {},
    this.boardColumns = const {},
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

  // Okvir mreže = RADNO VRIJEME salona za ovaj dan (za današnji i buduće dane);
  // za prošle dane ili kad radno vrijeme nije poznato → podrazumijevani okvir
  // (namjerno širok, jer se radno vrijeme moglo mijenjati u međuvremenu).
  List<WorkingHoursResponse> workingHours;
  try {
    workingHours = await api.getWorkingHours();
  } catch (_) {
    workingHours = const [];
  }
  final weekday = WeekDay.values[dayStart.weekday - 1]; // Pon=1 → index 0
  WorkingHoursResponse? salon;
  for (final w in workingHours) {
    if (w.dayOfWeek == weekday) {
      salon = w;
      break;
    }
  }
  final now = DateTime.now();
  final isPast = dayStart.isBefore(DateTime(now.year, now.month, now.day));
  int? primaryStart;
  int? primaryEnd;
  if (!isPast && salon != null) {
    primaryStart = _minutesOfDay(salon.opensAt);
    primaryEnd = _minutesOfDay(salon.closesAt);
  }
  final window = _dayWindow(dayStart, primaryStart, primaryEnd, appointments);

  // Vremenska mreža kroz izračunati okvir, na svakih kSlotMinutes.
  final slots = <AllSlot>[];
  var cursor = window.start;
  final end = window.end;
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
          servicePrice: a.servicePrice,
          startTime: aStart,
          endTime: aEnd,
          appointment: a,
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

  // Zbir dana po barberu (za footer): broj termina (bez pauza) i zarada od
  // ZAVRŠENIH termina. Grupišemo po employeeId.
  final totalsByBarber = <int, BarberDayTotals>{};
  for (final e in barbers.keys) {
    final mine = appointments
        .where((a) => a.employeeId == e && !isBreakNote(a.note))
        .toList();
    final completed =
        mine.where((a) => a.status == AppointmentStatus.completed).toList();
    totalsByBarber[e] = BarberDayTotals(
      appointmentCount: mine.length,
      completedCount: completed.length,
      earned: completed.fold<double>(0, (s, a) => s + (a.servicePrice ?? 0)),
    );
  }

  // ---- Kolone za „Pregled": svaki barber SVOJOM veličinom slota (trajanje) ----
  // Smjene svih barbera (za okvir kolone). Dijelimo isti provider kao prikaz.
  Map<int, ScheduleDayResponse> boardShifts = const {};
  try {
    boardShifts = await ref.watch(boardShiftsProvider.future);
  } catch (_) {
    boardShifts = const {};
  }

  // Trajanje termina po barberu (defaultAppointmentDuration; inače 15 min).
  final durationById = <int, int>{
    for (final e in employees)
      if (e.id != null)
        e.id!: (e.defaultAppointmentDuration != null &&
                e.defaultAppointmentDuration! > 0)
            ? e.defaultAppointmentDuration!
            : kSlotMinutes,
  };

  // Termini grupisani po barberu.
  final apptsByBarber = <int, List<AppointmentResponse>>{};
  for (final a in appointments) {
    final id = a.employeeId;
    if (id != null) (apptsByBarber[id] ??= <AppointmentResponse>[]).add(a);
  }

  final boardColumns = <int, List<BoardSlot>>{};
  for (final id in barbers.keys) {
    final size = durationById[id] ?? kSlotMinutes;
    final mine = apptsByBarber[id] ?? const <AppointmentResponse>[];
    final sched = boardShifts[id];

    // Okvir kolone (minuti od ponoći):
    //  1) smjena barbera za taj dan (ako je poznata — vrijedi i za prošle dane);
    //  2) ako smjene nema → radno vrijeme salona za taj dan;
    //  3) ako ni to nije poznato → ostaje prazno pa se okvir svede na termine.
    // (Ranije su prošli dani koristili fiksni 08–21, što je davalo pretrpan,
    //  uglavnom prazan prikaz sa nečitljivo sitnim ćelijama.)
    int? winStart;
    int? winEnd;
    final shStart = _minutesOfDay(sched?.shiftStart);
    final shEnd = _minutesOfDay(sched?.shiftEnd);
    if (shStart != null && shEnd != null && shEnd > shStart) {
      winStart = shStart;
      winEnd = shEnd;
    } else {
      final soStart = _minutesOfDay(salon?.opensAt);
      final soEnd = _minutesOfDay(salon?.closesAt);
      if (soStart != null && soEnd != null && soEnd > soStart) {
        winStart = soStart;
        winEnd = soEnd;
      }
    }

    // Uvijek proširi okvir da pokrije termine (da se nijedan ne sakrije).
    for (final a in mine) {
      final s = a.startTime?.toLocal();
      if (s != null) {
        final sm = s.hour * 60 + s.minute;
        final floor = sm - (sm % size);
        winStart = (winStart == null || floor < winStart) ? floor : winStart;
      }
      final e = a.endTime?.toLocal() ??
          s?.add(Duration(minutes: a.duration ?? size));
      if (e != null) {
        final em = (e.year == dayStart.year &&
                e.month == dayStart.month &&
                e.day == dayStart.day)
            ? e.hour * 60 + e.minute
            : 24 * 60;
        final ceil = ((em + size - 1) ~/ size) * size;
        winEnd = (winEnd == null || ceil > winEnd) ? ceil : winEnd;
      }
    }

    // Bez smjene i bez termina → prazna kolona (barber ne radi tog dana).
    if (winStart == null || winEnd == null || winEnd <= winStart) {
      boardColumns[id] = const [];
      continue;
    }
    winStart = winStart.clamp(0, 24 * 60).toInt();
    winEnd = winEnd.clamp(0, 24 * 60).toInt();

    final col = <BoardSlot>[];
    var cur = dayStart.add(Duration(minutes: winStart));
    final colEnd = dayStart.add(Duration(minutes: winEnd));
    while (cur.isBefore(colEnd)) {
      final slotEnd = cur.add(Duration(minutes: size));
      // Nađi termin ovog barbera koji pokriva slot [cur, slotEnd).
      SlotEntry? entry;
      for (final a in mine) {
        final aStart = a.startTime?.toLocal();
        final aEnd = a.endTime?.toLocal() ??
            aStart?.add(Duration(minutes: a.duration ?? size));
        if (aStart == null || aEnd == null) continue;
        if (aStart.isBefore(slotEnd) && aEnd.isAfter(cur)) {
          final cust = a.customerId != null ? customers[a.customerId] : null;
          entry = SlotEntry(
            employeeId: id,
            barberName: barberById[id],
            customerName: a.customerName ?? cust?.name,
            customerPhone: a.customerPhone ?? cust?.contactValue,
            serviceName: serviceById[a.serviceId],
            servicePrice: a.servicePrice,
            startTime: aStart,
            endTime: aEnd,
            appointment: a,
            isStart: !aStart.isBefore(cur) && aStart.isBefore(slotEnd),
            isBreak: isBreakNote(a.note),
          );
          break;
        }
      }
      col.add(BoardSlot(start: cur, end: slotEnd, entry: entry));
      cur = slotEnd;
    }
    boardColumns[id] = col;
  }

  return AllDaySchedule(
    day: dayStart,
    slots: slots,
    barbers: barbers,
    totalsByBarber: totalsByBarber,
    boardColumns: boardColumns,
  );
});

/// Smjene SVIH barbera za izabrani dan — da u „Pregled" prikazu svaka kolona
/// pokaže satnicu u okviru smjene tog barbera. Radi i za PROŠLE dane (server
/// vrati istorijsku smjenu ako je ima; ako ne, kolona pada na radno vrijeme
/// salona). Greške po pojedinom barberu se tiho preskaču — prikaz radi i sa
/// djelimičnim podacima.
final boardShiftsProvider =
    FutureProvider.autoDispose<Map<int, ScheduleDayResponse>>((ref) async {
  final api = ref.watch(apiServiceProvider);
  final dayStart = ref.watch(scheduleDateProvider);

  final employees = await ref.watch(employeesProvider.future);
  final ids = employees.map((e) => e.id).whereType<int>().toList();
  final day = _ymd(dayStart);

  final entries = await Future.wait(ids.map((id) async {
    try {
      final list = await api.getSchedule(employeeId: id, from: day, to: day);
      return list.isNotEmpty ? MapEntry(id, list.first) : null;
    } catch (_) {
      return null;
    }
  }));

  return {
    for (final e in entries)
      if (e != null) e.key: e.value,
  };
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
