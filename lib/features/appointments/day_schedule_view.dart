import 'dart:math';

import 'package:flutter/gestures.dart'; // PointerScrollEvent (Ctrl+točkić = zoom)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // tastatura (Ctrl +/−) i praćenje Ctrl-a
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/exceptions.dart';
import '../../models/models.dart';
import '../../services/notification_service.dart';
import '../../services/providers.dart';
import '../../shared/format.dart';
import '../../shared/widgets.dart';
import '../employees/employees_provider.dart';
import '../services/services_provider.dart';
import 'appointment_form.dart';
import 'appointment_search_screen.dart';
import 'barber_colors.dart';
import 'day_schedule_provider.dart';
import 'reminders.dart';
import 'slot_booking_form.dart';

/// Dnevni raspored kao tabela: redovi su slotovi od 15 minuta.
/// Lijeva kolona je vrijeme, desna pokazuje klijenta (ako je zauzeto).
/// Slobodna polja se biraju (od–do), pa se zakazuje preko dugmeta.
class DayScheduleView extends ConsumerStatefulWidget {
  /// Kad je `true`, prikaz se otvara preko cijelog ekrana (bez bočnog menija):
  /// dobija svoju naslovnu traku i zaključan je na raspored jednog barbera.
  final bool fullScreen;

  const DayScheduleView({super.key, this.fullScreen = false});

  @override
  ConsumerState<DayScheduleView> createState() => _DayScheduleViewState();
}

class _DayScheduleViewState extends ConsumerState<DayScheduleView> {
  // Visina jednog reda — fiksna, pa je ListView brži i tabela urednija.
  // Viša je jer u zauzetom polju stoji 4 linije (ime, telefon, cijena, vrijeme).
  static const double _rowHeight = 52;

  // Da li je „Filteri" panel otvoren (spušta se preko rasporeda).
  bool _filtersOpen = false;

  // Da li je Ctrl trenutno pritisnut. Dok jeste, gasimo skrol rasporeda pa
  // Ctrl + točkić miša služi ISKLJUČIVO za zoom (kao u Excelu).
  bool _ctrlHeld = false;

  // Trenutni zoom (množilac). Osvježava se na početku svakog build-a iz
  // scheduleZoomProvider-a, pa ga svi pomoćni graditelji koriste bez prosljeđivanja.
  double _z = 1.0;

  @override
  void initState() {
    super.initState();
    // Pratimo tastaturu samo da bismo znali kad je Ctrl pritisnut (za zoom točkićem).
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    super.dispose();
  }

  /// Osvježi „Ctrl pritisnut" stanje. Ne trošimo događaj (vraćamo `false`) —
  /// samo pratimo stanje da bismo znali kad točkić miša znači zoom (ne skrol).
  bool _onKeyEvent(KeyEvent event) {
    final held = HardwareKeyboard.instance.isControlPressed;
    if (held != _ctrlHeld && mounted) {
      setState(() => _ctrlHeld = held);
    }
    return false;
  }

  /// Skrol fizika rasporeda: dok je Ctrl pritisnut, skrol je isključen (točkić
  /// tada zumira). Inače podrazumijevana fizika.
  ScrollPhysics? get _schedulePhysics =>
      _ctrlHeld ? const NeverScrollableScrollPhysics() : null;

  // ---- Zoom rasporeda (Excel-stil) ----
  void _setZoom(double z) => ref.read(scheduleZoomProvider.notifier).state =
      z.clamp(kMinZoom, kMaxZoom).toDouble();
  void _zoomBy(double delta) => _setZoom(ref.read(scheduleZoomProvider) + delta);
  void _resetZoom() => _setZoom(1.0);

  // Izabrani opseg slotova (od _anchor do _focus).
  int? _anchor;
  int? _focus;

  int? get _lo =>
      (_anchor == null || _focus == null) ? null : min(_anchor!, _focus!);
  int? get _hi =>
      (_anchor == null || _focus == null) ? null : max(_anchor!, _focus!);

  bool _isSelected(int i) => _lo != null && i >= _lo! && i <= _hi!;

  void _clearSelection() => setState(() {
        _anchor = null;
        _focus = null;
      });

  /// Da li salon ne radi izabranog dana. Tada se zakazivanje NE nudi
  /// (računa se u `salonClosedForDayProvider` iz `/api/schedule`).
  bool get _salonClosedToday =>
      ref.read(salonClosedForDayProvider).valueOrNull ?? false;

  /// Ako je salon zatvoren tog dana, javi i vrati `true` (pozivalac prekida).
  bool _blockIfSalonClosed() {
    if (_salonClosedToday) {
      showSnack(context, 'Salon ne radi ovog dana — zakazivanje nije moguće.',
          isError: true);
      return true;
    }
    return false;
  }

  /// Tap na slobodan slot: prvi = početak, drugi = kraj (opseg).
  void _onTapFree(List<ScheduleSlot> slots, int index) {
    if (_blockIfSalonClosed()) return;
    setState(() {
      if (_anchor == null) {
        _anchor = index;
        _focus = index;
        return;
      }
      final lo = min(_anchor!, index);
      final hi = max(_anchor!, index);
      final allFree = [
        for (var k = lo; k <= hi; k++) slots[k],
      ].every((s) => !s.isBusy);
      if (allFree) {
        _focus = index;
      } else {
        _anchor = index;
        _focus = index;
      }
    });
  }

  // ===================== IZBOR U „PREGLED" TABLI (po barberu) =====================
  // U „Pregled" prikazu svaki barber ima svoju kolonu. Izbor slotova je vezan
  // za JEDNOG barbera (kolonu), pa pamtimo i koji je barber izabran.
  int? _boardBarber; // employeeId kolone u kojoj biramo
  int? _boardAnchor;
  int? _boardFocus;

  int? get _boardLo => (_boardAnchor == null || _boardFocus == null)
      ? null
      : min(_boardAnchor!, _boardFocus!);
  int? get _boardHi => (_boardAnchor == null || _boardFocus == null)
      ? null
      : max(_boardAnchor!, _boardFocus!);

  bool _boardIsSelected(int barberId, int i) =>
      _boardBarber == barberId &&
      _boardLo != null &&
      i >= _boardLo! &&
      i <= _boardHi!;

  void _clearBoardSelection() => setState(() {
        _boardBarber = null;
        _boardAnchor = null;
        _boardFocus = null;
      });

  /// Tap na slobodan slot u koloni barbera: prvi = početak, drugi = kraj opsega
  /// (samo ako su svi slotovi između slobodni kod tog barbera).
  void _onTapBoardFree(AllDaySchedule schedule, int barberId, int index) {
    if (_blockIfSalonClosed()) return;
    final col = schedule.boardColumns[barberId];
    if (col == null) return;
    setState(() {
      if (_boardBarber != barberId || _boardAnchor == null) {
        _boardBarber = barberId;
        _boardAnchor = index;
        _boardFocus = index;
        return;
      }
      final lo = min(_boardAnchor!, index);
      final hi = max(_boardAnchor!, index);
      final allFree = [
        for (var k = lo; k <= hi; k++) col[k],
      ].every((s) => !s.isBusy);
      if (allFree) {
        _boardFocus = index;
      } else {
        _boardAnchor = index;
        _boardFocus = index;
      }
    });
  }

  /// Učitaj adresar klijenata (za „našaptavanje" u formama zakazivanja).
  /// Ako učitavanje zakaže (npr. nema pristup), vraćamo praznu listu — forme
  /// tada padaju nazad na žive endpointe i nastavljaju da rade.
  Future<List<CustomerResponse>> _loadCustomerDirectory() async {
    try {
      return await ref.read(customerDirectoryProvider.future);
    } catch (_) {
      return const [];
    }
  }

  /// Osvježi OBA rasporeda (jednog barbera i zbirni), da promjene budu vidljive
  /// bez obzira na to koji je prikaz aktivan.
  void _refreshSchedules() {
    ref.invalidate(dayScheduleProvider);
    ref.invalidate(allDayScheduleProvider);
    // Uskladi i mobilne podsjetnike (otkaži/zakaži prema novom stanju).
    ref.invalidate(myReminderAppointmentsProvider);
  }

  /// Zakazivanje iz prikaza jednog barbera (koristi tekući izbor slotova).
  Future<void> _book(DaySchedule schedule) async {
    final lo = _lo, hi = _hi;
    if (lo == null || hi == null) return;
    await _startBooking(
      employeeId: schedule.employeeId,
      start: schedule.slots[lo].start,
      durationMinutes: (hi - lo + 1) * schedule.slotMinutes,
    );
  }

  /// Zakazivanje iz „Pregled" table (za izabranog barbera i njegov opseg).
  Future<void> _bookBoard(AllDaySchedule schedule) async {
    final barber = _boardBarber, lo = _boardLo, hi = _boardHi;
    if (barber == null || lo == null || hi == null) return;
    final col = schedule.boardColumns[barber];
    if (col == null || lo >= col.length || hi >= col.length) return;
    await _startBooking(
      employeeId: barber,
      start: col[lo].start,
      // Trajanje = od početka prvog do kraja zadnjeg izabranog slota (po trajanju barbera).
      durationMinutes: col[hi].end.difference(col[lo].start).inMinutes,
    );
  }

  /// Označi izabrani opseg u „Pregled" tabli kao pauzu (za izabranog barbera).
  Future<void> _markBoardBreak(AllDaySchedule schedule) async {
    final barber = _boardBarber, lo = _boardLo, hi = _boardHi;
    if (barber == null || lo == null || hi == null) return;
    final col = schedule.boardColumns[barber];
    if (col == null || lo >= col.length || hi >= col.length) return;

    final start = col[lo].start;
    final duration = col[hi].end.difference(col[lo].start).inMinutes;

    final ok = await confirmDialog(
      context,
      title: 'Pauza',
      message: 'Označiti izabrani period kao pauzu?',
      confirmText: 'Pauza',
    );
    if (!ok) return;

    final request = AppointmentRequest(
      employeeId: barber,
      startTime: start.toUtc(),
      duration: duration,
      servicePrice: 0,
      note: kBreakNote,
    );

    try {
      await ref.read(apiServiceProvider).createAppointment(request);
      _clearBoardSelection();
      _refreshSchedules();
      if (mounted) showSnack(context, 'Pauza dodata.');
    } catch (e) {
      if (mounted) {
        showSnack(context, ApiException.from(e).message, isError: true);
      }
    }
  }

  /// „Vanredni" termin za jednog barbera (dugme pored imena u „Pregled"):
  /// otvara punu formu gdje se sami biraju vrijeme i trajanje, pa kreira termin.
  Future<void> _bookExtra(int barberId) async {
    // Podrazumijevani početak: izabrani dan u 12:00, ali nikad u prošlosti
    // (biranje datuma u formi ne dozvoljava prošle dane).
    final viewed = ref.read(scheduleDateProvider);
    final now = DateTime.now();
    final viewedNoon = DateTime(viewed.year, viewed.month, viewed.day, 12);
    final initial =
        viewedNoon.isBefore(now) ? now.add(const Duration(hours: 1)) : viewedNoon;

    // Učitaj adresar klijenata za našaptavanje u formi.
    final directory = await _loadCustomerDirectory();
    if (!mounted) return;

    // Barber je zaključan (isAdmin:false + currentEmployeeId), pa se ne mijenja.
    final request = await showAppointmentForm(
      context,
      isAdmin: false,
      currentEmployeeId: barberId,
      employees: const [],
      initialStart: initial,
      api: ref.read(apiServiceProvider),
      customers: directory,
    );
    if (request == null) return;

    // Provjeri eventualni konflikt telefona (isto kao kod običnog zakazivanja).
    final resolved = await _resolveCustomerConflict(request);
    if (resolved == null) return;

    // Ista provjera rasporeda (van smjene → upozorenje, ne blokada).
    final ok = await _confirmWithinSchedule(
      employeeId: barberId,
      startLocal: resolved.startTime.toLocal(),
      durationMinutes: resolved.duration,
    );
    if (!ok) return;

    try {
      await ref.read(apiServiceProvider).createAppointment(resolved);
      _clearBoardSelection();
      _refreshSchedules();
      if (mounted) showSnack(context, 'Termin zakazan.');
    } catch (e) {
      if (mounted) {
        showSnack(context, ApiException.from(e).message, isError: true);
      }
    }
  }

  /// Zajednički tok zakazivanja: učitaj usluge, otvori formu, riješi konflikt
  /// telefona, kreiraj termin i osvježi prikaze.
  Future<void> _startBooking({
    required int? employeeId,
    required DateTime start,
    required int durationMinutes,
  }) async {
    // Provjera rasporeda: da li je termin u smjeni barbera i u radnom vremenu
    // salona. Backend NE blokira van rasporeda, pa samo upozorimo i pitamo.
    final okSchedule = await _confirmWithinSchedule(
      employeeId: employeeId,
      startLocal: start,
      durationMinutes: durationMinutes,
    );
    if (!okSchedule) return;

    // Učitaj usluge za padajući meni. Ako učitavanje ne uspije (npr. keširana
    // greška od ranije), pokušaj jednom svjež poziv. Ako i to padne, ipak
    // otvaramo formu sa praznom listom — usluga nije obavezna za termin.
    List<ServiceEntityResponse> services;
    try {
      services = await ref.read(servicesProvider.future);
    } catch (_) {
      try {
        services = await ref.refresh(servicesProvider.future);
      } catch (_) {
        services = const [];
      }
    }
    // Adresar klijenata za našaptavanje (ime/telefon) u formi.
    final directory = await _loadCustomerDirectory();
    if (!mounted) return;

    final request = await showSlotBookingForm(
      context,
      startTime: start,
      durationMinutes: durationMinutes,
      employeeId: employeeId,
      services: services,
      api: ref.read(apiServiceProvider),
      customers: directory,
    );
    if (request == null) return;

    // Provjeri da li telefon već postoji pod drugim imenom (i pitaj korisnika).
    final resolved = await _resolveCustomerConflict(request);
    if (resolved == null) return; // korisnik otkazao

    try {
      await ref.read(apiServiceProvider).createAppointment(resolved);
      _clearSelection();
      _clearBoardSelection();
      _refreshSchedules();
      if (mounted) showSnack(context, 'Termin zakazan.');
    } catch (e) {
      if (mounted) showSnack(context, ApiException.from(e).message, isError: true);
    }
  }

  /// Ako uneseni telefon već postoji u bazi pod DRUGIM imenom, pita korisnika
  /// da li da koristi postojećeg klijenta ili da mu ažurira ime. Vraća zahtjev
  /// (po potrebi sa `customerId`) ili `null` ako je korisnik otkazao.
  Future<AppointmentRequest?> _resolveCustomerConflict(
      AppointmentRequest request) async {
    final phone = request.customerPhone?.trim();
    final newName = request.customerName?.trim();

    // Bez telefona ili ako je klijent već izabran — ništa ne provjeravamo.
    if (request.customerId != null || phone == null || phone.isEmpty) {
      return request;
    }

    // Potraži postojećeg klijenta po telefonu. Ako endpoint nije dostupan
    // (npr. backend još nije ažuriran), ponašaj se kao do sada.
    CustomerResponse? existing;
    try {
      final hits = await ref.read(apiServiceProvider).findCustomersByPhone(phone);
      if (hits.isNotEmpty) existing = hits.first;
    } catch (_) {
      return request;
    }

    if (existing == null) return request; // nema poklapanja → server pravi novog

    final existingName = (existing.name ?? '').trim();
    // Isto ime (ili novo nije uneseno) → samo veži za postojećeg klijenta.
    if (newName == null ||
        newName.isEmpty ||
        existingName.toLowerCase() == newName.toLowerCase()) {
      return request.copyWith(customerId: existing.id);
    }

    // Konflikt: isti telefon, drugo ime → pitaj korisnika.
    if (!mounted) return null;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Broj već postoji'),
        content: Text(
          'Broj $phone već koristi klijent „$existingName".\n\n'
          'Što želite da uradite?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Otkaži'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'existing'),
            child: Text('Koristi: $existingName'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'update'),
            child: Text('Ažuriraj ime u: $newName'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'new'),
            child: const Text('Napravi novog'),
          ),
        ],
      ),
    );

    switch (choice) {
      case 'existing':
        return request.copyWith(customerId: existing.id);
      case 'update':
        // Ažuriraj ime postojećeg klijenta, pa veži termin za njega.
        try {
          await ref.read(apiServiceProvider).updateCustomer(
                existing.id!,
                CustomerRequest(
                  name: newName,
                  contactValue: existing.contactValue ?? phone,
                  contactType: existing.contactType,
                  sellingPlaceId: existing.sellingPlaceId,
                ),
              );
        } catch (e) {
          if (mounted) {
            showSnack(context, ApiException.from(e).message, isError: true);
          }
          return null;
        }
        return request.copyWith(customerId: existing.id);
      case 'new':
        // Napravi NOVOG klijenta sa istim brojem, pa veži termin za njega.
        try {
          final created = await ref.read(apiServiceProvider).createCustomer(
                CustomerRequest(name: newName, contactValue: phone),
              );
          return request.copyWith(customerId: created.id);
        } catch (e) {
          if (mounted) {
            showSnack(context, ApiException.from(e).message, isError: true);
          }
          return null;
        }
      default:
        return null; // otkazano
    }
  }

  /// Označi izabrane slotove kao pauzu (termin bez klijenta, sa oznakom PAUZA).
  Future<void> _markBreak(DaySchedule schedule) async {
    final lo = _lo, hi = _hi;
    if (lo == null || hi == null) return;

    final start = schedule.slots[lo].start;
    final duration = (hi - lo + 1) * schedule.slotMinutes;

    final ok = await confirmDialog(
      context,
      title: 'Pauza',
      message: 'Označiti izabrani period kao pauzu?',
      confirmText: 'Pauza',
    );
    if (!ok) return;

    final request = AppointmentRequest(
      employeeId: schedule.employeeId,
      startTime: start.toUtc(),
      duration: duration,
      servicePrice: 0,
      note: kBreakNote,
    );

    try {
      await ref.read(apiServiceProvider).createAppointment(request);
      _clearSelection();
      _refreshSchedules();
      if (mounted) showSnack(context, 'Pauza dodata.');
    } catch (e) {
      if (mounted) {
        showSnack(context, ApiException.from(e).message, isError: true);
      }
    }
  }

  /// Tap na zauzet slot: pauza → ponudi uklanjanje; termin → promjena statusa.
  Future<void> _onTapBusy(
    AppointmentResponse appt, {
    String? customerName,
    String? customerPhone,
    String? serviceName,
  }) async {
    if (isBreakNote(appt.note)) {
      await _removeBreak(appt);
    } else {
      await _changeStatus(
        appt,
        customerName: customerName,
        customerPhone: customerPhone,
        serviceName: serviceName,
      );
    }
  }

  /// Ukloni pauzu (briše termin-pauzu).
  Future<void> _removeBreak(AppointmentResponse appt) async {
    final id = appt.id;
    if (id == null) return;
    final ok = await confirmDialog(
      context,
      title: 'Ukloni pauzu',
      message: 'Da li želite da uklonite ovu pauzu?',
      confirmText: 'Ukloni',
    );
    if (!ok) return;
    try {
      await ref.read(apiServiceProvider).deleteAppointment(id);
      _refreshSchedules();
      if (mounted) showSnack(context, 'Pauza uklonjena.');
    } catch (e) {
      if (mounted) {
        showSnack(context, ApiException.from(e).message, isError: true);
      }
    }
  }

  /// Tap na termin: ponudi IZMJENU termina ili promjenu statusa.
  Future<void> _changeStatus(
    AppointmentResponse appt, {
    String? customerName,
    String? customerPhone,
    String? serviceName,
  }) async {
    final id = appt.id;
    if (id == null) return;

    // Detalji za informativni dio. Ime/telefon/uslugu prvo uzimamo iz REDA
    // termina (već razriješeni), jer ih sam `appt` često nema (server ne vraća
    // uvijek, a getCustomer barberima vraća 403). Uslugu, ako fali, razriješimo
    // iz serviceId (keširani servisi). Kraj: endTime ili start + trajanje.
    final custName = (customerName?.trim().isNotEmpty ?? false)
        ? customerName!.trim()
        : ((appt.customerName?.trim().isNotEmpty ?? false)
            ? appt.customerName!.trim()
            : null);
    final custPhone = (customerPhone?.trim().isNotEmpty ?? false)
        ? customerPhone!.trim()
        : ((appt.customerPhone?.trim().isNotEmpty ?? false)
            ? appt.customerPhone!.trim()
            : null);
    var svcName =
        (serviceName?.trim().isNotEmpty ?? false) ? serviceName!.trim() : null;
    if (svcName == null && appt.serviceId != null) {
      try {
        final services = await ref.read(servicesProvider.future);
        for (final s in services) {
          if (s.id == appt.serviceId) {
            svcName = s.name;
            break;
          }
        }
      } catch (_) {
        // usluga ostaje nepoznata — prikažemo „—"
      }
    }
    final start = appt.startTime?.toLocal();
    final end = appt.endTime?.toLocal() ??
        (start != null && appt.duration != null
            ? start.add(Duration(minutes: appt.duration!))
            : null);
    if (!mounted) return;

    final result = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true, // da detalji stanu i na malom ekranu (skroluje)
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Termin',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Izmijeni termin'),
                onTap: () => Navigator.pop(ctx, 'edit'),
              ),
              const Divider(height: 1),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Promijeni status',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              for (final s in AppointmentStatus.values)
                ListTile(
                  leading: Icon(_statusIcon(s)),
                  title: Text(s.label),
                  trailing: appt.status == s
                      ? const Icon(Icons.check, color: Colors.green)
                      : null,
                  onTap: () => Navigator.pop(ctx, s),
                ),
              const Divider(height: 1),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Detalji termina',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              _detailTile(Icons.content_cut, 'Usluga', svcName ?? '—'),
              _detailTile(Icons.payments_outlined, 'Cijena',
                  Format.money(appt.servicePrice)),
              _detailTile(Icons.timelapse_outlined, 'Trajanje',
                  appt.duration != null ? '${appt.duration} min' : '—'),
              _detailTile(
                  Icons.schedule,
                  'Vrijeme',
                  start != null
                      ? '${Format.time(start)} – ${Format.time(end)}'
                      : '—'),
              _detailTile(Icons.person_outline, 'Klijent', custName ?? '—'),
              _detailTile(Icons.phone_outlined, 'Telefon', custPhone ?? '—'),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

    // Izmjena svih stavki termina.
    if (result == 'edit') {
      await _editAppointment(appt);
      return;
    }

    // Promjena statusa.
    if (result is! AppointmentStatus || result == appt.status) return;
    final selected = result;
    try {
      await ref
          .read(apiServiceProvider)
          .changeAppointmentStatus(id, StatusChangeRequest(status: selected));
      // Status ažuriran → odmah otkaži podsjetnik za taj termin (lokalno).
      if (selected != AppointmentStatus.scheduled) {
        notificationService.cancel(id);
      }
      _refreshSchedules();
      if (mounted) showSnack(context, 'Status: ${selected.label}.');
    } catch (e) {
      if (mounted) {
        showSnack(context, ApiException.from(e).message, isError: true);
      }
    }
  }

  /// Jedan red informativnih detalja termina (ikona + naziv + vrijednost).
  /// Responzivno: naziv fiksne širine, vrijednost se širi i skraćuje po potrebi.
  Widget _detailTile(IconData icon, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.hintColor),
          const SizedBox(width: 12),
          SizedBox(
            width: 76,
            child: Text(label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.hintColor)),
          ),
          Expanded(
            child: Text(value,
                style: theme.textTheme.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  /// Izmjena postojećeg termina (sve stavke): otvori formu popunjenu podacima
  /// termina, pa pošalji PUT na server.
  Future<void> _editAppointment(AppointmentResponse appt) async {
    final id = appt.id;
    if (id == null) return;
    final auth = ref.read(authControllerProvider);

    // Usluge (za padajući izbor) — ako ne uspije, forma radi i bez njih.
    List<ServiceEntityResponse> services;
    try {
      services = await ref.read(servicesProvider.future);
    } catch (_) {
      services = const [];
    }
    // Zaposleni (da admin može promijeniti barbera).
    List<EmployeeResponse> employees = const [];
    if (auth.isAdmin) {
      try {
        employees = await ref.read(employeesProvider.future);
      } catch (_) {}
    }
    final directory = await _loadCustomerDirectory();
    if (!mounted) return;

    final request = await showAppointmentForm(
      context,
      isAdmin: auth.isAdmin,
      currentEmployeeId: auth.employeeId,
      employees: employees,
      api: ref.read(apiServiceProvider),
      customers: directory,
      existing: appt,
      services: services,
    );
    if (request == null) return;

    // Ista provjera konflikta telefona kao kod kreiranja.
    final resolved = await _resolveCustomerConflict(request);
    if (resolved == null) return;

    try {
      await ref.read(apiServiceProvider).updateAppointment(id, resolved);
      _refreshSchedules();
      if (mounted) showSnack(context, 'Termin izmijenjen.');
    } catch (e) {
      if (mounted) {
        showSnack(context, ApiException.from(e).message, isError: true);
      }
    }
  }

  // Ikonica za svaki status (radi preglednosti u listi).
  IconData _statusIcon(AppointmentStatus s) => switch (s) {
        AppointmentStatus.scheduled => Icons.event_available,
        AppointmentStatus.completed => Icons.check_circle_outline,
        AppointmentStatus.cancelled => Icons.cancel_outlined,
        AppointmentStatus.noShow => Icons.person_off_outlined,
      };

  // Mali bedž statusa (boja + naziv) — prikazujemo uz zauzet termin.
  Widget _statusBadge(AppointmentStatus s) {
    final color = switch (s) {
      AppointmentStatus.completed => Colors.green,
      AppointmentStatus.cancelled => Colors.red,
      AppointmentStatus.noShow => Colors.orange,
      AppointmentStatus.scheduled => Colors.blue,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        s.label,
        style: TextStyle(
            fontSize: 10, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  // Pomjeri prikazani dan za +/- dana (i poništi tekući izbor slotova).
  void _shiftDay(int days) {
    _clearSelection();
    final d = ref.read(scheduleDateProvider);
    final next = d.add(Duration(days: days));
    // Normalizujemo na ponoć (izbjegavamo pomjeranja zbog ljetnjeg vremena).
    ref.read(scheduleDateProvider.notifier).state =
        DateTime(next.year, next.month, next.day);
  }

  // Otvori kalendar za biranje datuma.
  Future<void> _pickDate() async {
    final current = ref.read(scheduleDateProvider);
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      _clearSelection();
      ref.read(scheduleDateProvider.notifier).state =
          DateTime(picked.year, picked.month, picked.day);
    }
  }

  // Otvori ekran za pretragu termina po klijentu.
  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AppointmentSearchScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    // Admin može da uključi zbirni prikaz svih barbera. (Puni ekran zadržava
    // izabrani prikaz — jednog barbera ili tablu — samo bez bočnog menija.)
    final showAll = auth.isAdmin && ref.watch(scheduleShowAllProvider);
    final view = ref.watch(scheduleViewProvider);
    final scheduleAsync = ref.watch(dayScheduleProvider);
    // „Gledamo" i status zatvorenosti salona da se prikaz (npr. FAB) osvježi čim
    // se učita — pa se na zatvoren dan zakazivanje ne nudi.
    ref.watch(salonClosedForDayProvider);
    // Osvježi trenutni zoom (koriste ga svi pomoćni graditelji preko `_z`).
    _z = ref.watch(scheduleZoomProvider);

    final lo = _lo, hi = _hi;
    // Trajanje izbora zavisi od veličine slota (defaultAppointmentDuration barbera).
    final slotMin = scheduleAsync.valueOrNull?.slotMinutes ?? kSlotMinutes;
    final minutes = (lo != null && hi != null) ? (hi - lo + 1) * slotMin : 0;

    return Scaffold(
      floatingActionButton: _buildFab(showAll, view, scheduleAsync, minutes),
      // Tastaturne prečice za zoom (Ctrl +, Ctrl −, Ctrl 0) — kao u Excelu.
      body: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.equal, control: true):
              () => _zoomBy(kZoomStep),
          const SingleActivator(LogicalKeyboardKey.add, control: true):
              () => _zoomBy(kZoomStep),
          const SingleActivator(LogicalKeyboardKey.numpadAdd, control: true):
              () => _zoomBy(kZoomStep),
          const SingleActivator(LogicalKeyboardKey.minus, control: true):
              () => _zoomBy(-kZoomStep),
          const SingleActivator(LogicalKeyboardKey.numpadSubtract,
              control: true): () => _zoomBy(-kZoomStep),
          const SingleActivator(LogicalKeyboardKey.digit0, control: true):
              _resetZoom,
        },
        child: Focus(
          autofocus: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTopBar(showAll),
              Expanded(
                child: Stack(
                  children: [
                    // Raspored popunjava cijeli prostor.
                    Positioned.fill(
                      child: _buildScheduleArea(showAll, scheduleAsync),
                    ),
                    // „Filteri" panel se spušta preko rasporeda (uz zatamnjenje).
                    if (_filtersOpen) _buildFilterOverlay(showAll),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Raspored (zbirni ili jednog barbera), obmotan `Listener`-om da Ctrl+točkić
  /// miša radi zoom (kao u Excelu). Dok je Ctrl pritisnut, skrol je isključen
  /// (vidi [_schedulePhysics]), pa točkić zumira umjesto da skroluje.
  Widget _buildScheduleArea(
      bool showAll, AsyncValue<DaySchedule> scheduleAsync) {
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent &&
            HardwareKeyboard.instance.isControlPressed) {
          // Točkić gore (negativan dy) = uvećaj, dolje = smanji.
          _zoomBy(event.scrollDelta.dy < 0 ? kZoomStep : -kZoomStep);
        }
      },
      child: showAll ? _buildAllTable() : _buildSingleSchedule(scheduleAsync),
    );
  }

  /// Da li su dva datuma isti kalendarski dan.
  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Raspored jednog barbera. Ako imamo podatke za IZABRANI dan → prikaži ih
  /// (bez bljeska pri osvježavanju istog dana). Inače (prvo učitavanje ili
  /// promjena datuma pa su podaci za drugi dan) → makaze-loader.
  Widget _buildSingleSchedule(AsyncValue<DaySchedule> async) {
    final selected = ref.watch(scheduleDateProvider);
    final v = async.valueOrNull;
    if (v != null && _sameDay(v.day, selected)) {
      return _buildTable(v);
    }
    if (async.hasError && v == null) {
      return ErrorView(
        message: async.error.toString(),
        onRetry: () => ref.invalidate(dayScheduleProvider),
      );
    }
    return const LoadingView();
  }

  /// Tanka gornja traka: navigacija dana + zoom + dugme „Filteri" + cijeli ekran.
  /// Namjerno je niska (~48 px) da rasporedu ostane maksimum prostora.
  Widget _buildTopBar(bool showAll) {
    final theme = Theme.of(context);
    final auth = ref.watch(authControllerProvider);
    final date = ref.watch(scheduleDateProvider);

    // Naziv dana pored datuma; za današnji dan piše „Danas".
    final now = DateTime.now();
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;
    final dayLabel = isToday ? 'Danas' : Format.weekday(date);

    // Ako admin gleda jednog barbera, pokaži čije termine gleda (uz boju).
    String? barberName;
    if (auth.isAdmin && !showAll) {
      final id = ref.watch(scheduleEmployeeProvider);
      final employees = ref.watch(employeesProvider).valueOrNull;
      if (id != null && employees != null) {
        for (final e in employees) {
          if (e.id == id) {
            barberName = e.name;
            break;
          }
        }
      }
    }

    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
      child: SizedBox(
        height: 48,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Uski ekran (telefon): sažimamo — kratak datum, „Filteri" kao ikona,
            // zoom bez procenta, bez cijelog ekrana i imena barbera. Tako sve stane.
            final compact = constraints.maxWidth < 560;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                children: [
                  // Lijeva grupa [‹ datum › (barber)] — u Expanded-u da popuni
                  // preostali prostor (desne kontrole ostaju uz desnu ivicu i
                  // NIKAD se ne prelijeju izvan ekrana na telefonu).
                  Expanded(
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          tooltip: 'Prethodni dan',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _shiftDay(-1),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.calendar_today, size: 18),
                          label: Text(
                            // Uvijek: naziv dana + pun datum (npr. „Ponedjeljak,
                            // 27.07.2026."). Za današnji dan naziv je „Danas".
                            '$dayLabel, ${Format.date(date)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onPressed: _pickDate,
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          tooltip: 'Sljedeći dan',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _shiftDay(1),
                        ),
                        // Ime barbera — samo na širem ekranu (na uskom nema mjesta).
                        if (!compact && barberName != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: barberColor(
                                  ref.read(scheduleEmployeeProvider)),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              barberName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Zoom kontrole (na uskom bez procenta — samo − i +).
                  _buildZoomCluster(compact),
                  // „Filteri": ikona na uskom, tekst + cijeli ekran na širokom.
                  if (compact)
                    IconButton(
                      icon:
                          Icon(_filtersOpen ? Icons.expand_less : Icons.tune),
                      tooltip: 'Filteri',
                      onPressed: () =>
                          setState(() => _filtersOpen = !_filtersOpen),
                    )
                  else ...[
                    const SizedBox(width: 4),
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _filtersOpen = !_filtersOpen),
                      icon: Icon(_filtersOpen ? Icons.expand_less : Icons.tune,
                          size: 18),
                      label: const Text('Filteri'),
                    ),
                    IconButton(
                      icon: Icon(widget.fullScreen
                          ? Icons.fullscreen_exit
                          : Icons.fullscreen),
                      tooltip: widget.fullScreen
                          ? 'Zatvori cijeli ekran'
                          : 'Cijeli ekran',
                      onPressed: () {
                        if (widget.fullScreen) {
                          Navigator.of(context).maybePop();
                        } else {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  const DayScheduleView(fullScreen: true),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Zoom klaster: [−] (procenat) [+]. Tap na procenat vraća na 100%.
  /// Na uskom ekranu ([compact]) izostavljamo procenat da uštedimo prostor.
  Widget _buildZoomCluster(bool compact) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove, size: 18),
          tooltip: 'Umanji',
          visualDensity: VisualDensity.compact,
          onPressed: _z <= kMinZoom ? null : () => _zoomBy(-kZoomStep),
        ),
        // Procenat (tap = reset na 100%) — skrivamo ga na uskom ekranu.
        if (!compact)
          Tooltip(
            message: 'Vrati na 100%',
            child: InkWell(
              onTap: _resetZoom,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text(
                  '${(_z * 100).round()}%',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        IconButton(
          icon: const Icon(Icons.add, size: 18),
          tooltip: 'Uvećaj',
          visualDensity: VisualDensity.compact,
          onPressed: _z >= kMaxZoom ? null : () => _zoomBy(kZoomStep),
        ),
      ],
    );
  }

  /// Zatamnjenje + „Filteri" panel koji se spušta preko rasporeda.
  Widget _buildFilterOverlay(bool showAll) {
    return Positioned.fill(
      child: Stack(
        children: [
          // Zatamnjenje — tap bilo gdje van panela zatvara.
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => _filtersOpen = false),
              child: Container(color: Colors.black.withOpacity(0.35)),
            ),
          ),
          // Panel poravnat uz vrh, sa blagim „padom" (slide + fade).
          Align(
            alignment: Alignment.topCenter,
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              tween: Tween(begin: 0, end: 1),
              builder: (context, t, child) => Opacity(
                opacity: t,
                child: Transform.translate(
                    offset: Offset(0, (t - 1) * 12), child: child),
              ),
              child: _buildFilterPanel(showAll),
            ),
          ),
        ],
      ),
    );
  }

  /// Sadržaj „Filteri" panela: prikaz (Pregled/Mreža/Lista), izbor barbera,
  /// pretraga i info o smjeni/radnom vremenu.
  Widget _buildFilterPanel(bool showAll) {
    final theme = Theme.of(context);
    final auth = ref.watch(authControllerProvider);
    final view = ref.watch(scheduleViewProvider);
    final labelStyle = theme.textTheme.labelMedium
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Material(
      elevation: 8,
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Naslov + zatvori.
            Row(
              children: [
                Text('Prikaz i filteri',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Zatvori',
                  onPressed: () => setState(() => _filtersOpen = false),
                ),
              ],
            ),
            if (auth.isAdmin) ...[
              // Način prikaza — bira se samo kad gledamo sve barbere.
              if (showAll) ...[
                Text('Prikaz', style: labelStyle),
                const SizedBox(height: 6),
                SegmentedButton<AllScheduleView>(
                  showSelectedIcon: false,
                  style:
                      const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: const [
                    ButtonSegment(
                      value: AllScheduleView.overview,
                      icon: Icon(Icons.dashboard_outlined),
                      label: Text('Pregled'),
                    ),
                    ButtonSegment(
                      value: AllScheduleView.grid,
                      icon: Icon(Icons.grid_on),
                      label: Text('Mreža'),
                    ),
                    ButtonSegment(
                      value: AllScheduleView.list,
                      icon: Icon(Icons.view_list),
                      label: Text('Lista'),
                    ),
                  ],
                  selected: {view},
                  onSelectionChanged: (s) =>
                      ref.read(scheduleViewProvider.notifier).state = s.first,
                ),
                const SizedBox(height: 14),
              ],
              // Izbor barbera (Svi barberi / pojedinačno).
              Text('Barber', style: labelStyle),
              const SizedBox(height: 6),
              _buildBarberChips(showAll),
              const SizedBox(height: 14),
            ],
            // Pretraga klijenta.
            OutlinedButton.icon(
              icon: const Icon(Icons.search, size: 18),
              label: const Text('Pretraga klijenta'),
              onPressed: () {
                setState(() => _filtersOpen = false);
                _openSearch();
              },
            ),
            // Info o smjeni/radnom vremenu (za prikaz jednog barbera).
            _buildFilterInfo(showAll),
          ],
        ),
      ),
    );
  }

  /// Čipovi za izbor barbera: „Svi barberi" + po jedan za svakog zaposlenog.
  /// Klik prebacuje prikaz; panel ostaje otvoren (raspored se osvježi u pozadini).
  Widget _buildBarberChips(bool showAll) {
    final employees = ref.watch(employeesProvider).valueOrNull ?? const [];
    final selectedId = ref.watch(scheduleEmployeeProvider);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: const Text('Svi barberi'),
          selected: showAll,
          onSelected: (_) => _showAllBarbers(),
        ),
        for (final e in employees)
          if (e.id != null)
            ChoiceChip(
              avatar: CircleAvatar(
                backgroundColor: barberColor(e.id),
                radius: 7,
              ),
              label: Text(e.name ?? 'Barber ${e.id}'),
              selected: !showAll && selectedId == e.id,
              onSelected: (_) => _selectBarber(e.id!),
            ),
      ],
    );
  }

  /// Info o smjeni/radnom vremenu unutar panela (samo za prikaz jednog barbera).
  Widget _buildFilterInfo(bool showAll) {
    if (showAll) return const SizedBox.shrink();
    final info = ref.watch(dayScheduleInfoProvider).valueOrNull;
    if (info == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: _buildScheduleBanner(info),
    );
  }

  /// Plutajuće dugme zavisi od prikaza:
  /// - jedan barber sa izborom slotova → poništi/pauza/zakaži;
  /// - „Pregled" tabla sa izborom u koloni barbera → poništi/zakaži za tog barbera.
  Widget? _buildFab(bool showAll, AllScheduleView view,
      AsyncValue<DaySchedule> scheduleAsync, int minutes) {
    // Salon ne radi tog dana → ne nudimo dugme za zakazivanje.
    if (_salonClosedToday) return null;
    // Jedan barber.
    if (!showAll && _lo != null && scheduleAsync.hasValue) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'clear',
            onPressed: _clearSelection,
            tooltip: 'Poništi izbor',
            child: const Icon(Icons.close),
          ),
          const SizedBox(width: 12),
          FloatingActionButton.small(
            heroTag: 'break',
            onPressed: () => _markBreak(scheduleAsync.value!),
            tooltip: 'Označi kao pauzu',
            child: const Icon(Icons.free_breakfast_outlined),
          ),
          const SizedBox(width: 12),
          FloatingActionButton.extended(
            heroTag: 'book',
            onPressed: () => _book(scheduleAsync.value!),
            icon: const Icon(Icons.check),
            label: Text('Zakaži ($minutes min)'),
          ),
        ],
      );
    }

    // „Pregled" tabla — izbor u koloni jednog barbera.
    if (showAll &&
        view == AllScheduleView.overview &&
        _boardBarber != null &&
        _boardLo != null) {
      final allSched = ref.read(allDayScheduleProvider).valueOrNull;
      if (allSched != null) {
        final col = allSched.boardColumns[_boardBarber];
        final boardMinutes = (col != null &&
                _boardLo! < col.length &&
                _boardHi! < col.length)
            ? col[_boardHi!].end.difference(col[_boardLo!].start).inMinutes
            : 0;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FloatingActionButton.small(
              heroTag: 'clearBoard',
              onPressed: _clearBoardSelection,
              tooltip: 'Poništi izbor',
              child: const Icon(Icons.close),
            ),
            const SizedBox(width: 12),
            FloatingActionButton.small(
              heroTag: 'breakBoard',
              onPressed: () => _markBoardBreak(allSched),
              tooltip: 'Označi kao pauzu',
              child: const Icon(Icons.free_breakfast_outlined),
            ),
            const SizedBox(width: 12),
            FloatingActionButton.extended(
              heroTag: 'bookBoard',
              onPressed: () => _bookBoard(allSched),
              icon: const Icon(Icons.check),
              label: Text('Zakaži ($boardMinutes min)'),
            ),
          ],
        );
      }
    }
    return null;
  }

  // Izaberi jednog barbera (iz „Filteri" panela) → prikaži samo njegov raspored.
  void _selectBarber(int employeeId) {
    _clearSelection();
    ref.read(scheduleEmployeeProvider.notifier).state = employeeId;
    ref.read(scheduleShowAllProvider.notifier).state = false;
  }

  // Vrati se na zbirni prikaz svih barbera.
  void _showAllBarbers() {
    _clearSelection();
    ref.read(scheduleShowAllProvider.notifier).state = true;
  }

  // ===================== ZBIRNA TABELA: SVI BARBERI =====================

  /// Zbirni prikaz svih barbera. Način prikaza (Pregled/Mreža/Lista) i izbor
  /// barbera su u „Filteri" panelu, pa ovdje ostaje samo tijelo (bez naslova) —
  /// da rasporedu ostane sav prostor.
  Widget _buildAllTable() {
    final scheduleAsync = ref.watch(allDayScheduleProvider);
    final view = ref.watch(scheduleViewProvider);
    final selected = ref.watch(scheduleDateProvider);
    final v = scheduleAsync.valueOrNull;
    // Podaci za IZABRANI dan → prikaži (bez bljeska pri osvježavanju istog dana);
    // inače (prvo učitavanje / promjena datuma) → makaze-loader.
    if (v != null && _sameDay(v.day, selected)) {
      return _buildAllBody(v, view);
    }
    if (scheduleAsync.hasError && v == null) {
      return ErrorView(
        message: scheduleAsync.error.toString(),
        onRetry: () => ref.invalidate(allDayScheduleProvider),
      );
    }
    return const LoadingView();
  }

  /// Bira tijelo zbirnog prikaza prema izabranom načinu (mreža/lista/pregled).
  Widget _buildAllBody(AllDaySchedule schedule, AllScheduleView view) {
    switch (view) {
      case AllScheduleView.grid:
        return _buildDetailedGrid(schedule);
      case AllScheduleView.list:
        final theme = Theme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _tableHeader(theme),
            Expanded(
              child: ListView.builder(
                physics: _schedulePhysics,
                itemCount: schedule.slots.length,
                itemBuilder: (context, i) => _buildAllRow(schedule.slots[i]),
              ),
            ),
          ],
        );
      case AllScheduleView.overview:
        return _buildOverview(schedule);
    }
  }

  // ===================== PREGLED: TABLA PO BARBERIMA =====================

  /// „Pregled": svaki barber ima svoju kolonu. Svaka kolona prikazuje SAMO
  /// slotove svoje smjene i to od vrha (bez praznog prostora do početka smjene),
  /// pa se odmah vidi gdje smjena počinje. Zaglavlja i footeri su fiksni.
  ///
  /// Kolone su nezavisne (različite dužine), pa svaka počinje na vrhu. Da bismo
  /// izbjegli poznati problem sa intrinsics-om (SingleChildScrollView + Row of
  /// Expanded kolona), kolone imaju FIKSNU širinu (računamo je iz LayoutBuilder-a).
  Widget _buildOverview(AllDaySchedule schedule) {
    // Kolone = SVI barberi (i oni bez termina), da bi se moglo zakazati kod
    // bilo koga. Sortirano po imenu.
    final ids = schedule.barbers.keys.toList()
      ..sort((a, b) =>
          (schedule.barbers[a] ?? '').compareTo(schedule.barbers[b] ?? ''));

    if (ids.isEmpty) {
      return const EmptyView(
        message: 'Nema zaposlenih za prikaz.',
        icon: Icons.people_outline,
      );
    }

    const headerH = 40.0; // visina zaglavlja kolona
    const footerH = 50.0; // visina footera (broj termina + zarada)
    // Minimalna širina kolone da tekst (ime/telefon) bude čitljiv. Ispod ove
    // širine kolone se NE stiskaju — dobiju ovu širinu i prikaz se skroluje
    // bočno (npr. na telefonu). Kolona = 40px satnica + ~padding, pa ostaje
    // dovoljno za tekst tek preko ~165px.
    const minColW = 168.0;
    const minCellH = 14.0; // apsolutni minimum (dozvoljen tek kad se zumira napolje)
    const readableCellH = 27.0; // čitljiva osnova (satnica + red stanu)

    // Najduža kolona (najviše slotova) — po njoj računamo „uklapanje" cijelog dana.
    var maxRows = 1;
    for (final id in ids) {
      final n = schedule.boardColumns[id]?.length ?? 0;
      if (n > maxRows) maxRows = n;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Visina koju ima TIJELO (bez zaglavlja i footera).
        final bodyH = (constraints.maxHeight - headerH - footerH)
            .clamp(0.0, double.infinity);
        // Auto-uklapanje: podijeli visinu tijela na broj redova. Ali NE ispod
        // čitljive granice — inače na dugačkim danima (npr. prošli dan sa širokim
        // okvirom) ćelije postanu nečitljivo sitne i oznake vremena nestanu.
        // Preko granice se skroluje. Zoom skalira osnovu (zoom − može i sitnije,
        // ako korisnik baš želi da sve stane bez skrola).
        final fitCellH = maxRows > 0 ? bodyH / maxRows : readableCellH;
        final baseCellH = fitCellH < readableCellH ? readableCellH : fitCellH;
        final cellH =
            (baseCellH * _z).clamp(minCellH, double.infinity).toDouble();

        // Širina kolone: podijeli ravnomjerno; ako je preusko — min širina + skrol.
        final fits = ids.length * minColW <= constraints.maxWidth;
        final colW = fits ? constraints.maxWidth / ids.length : minColW;
        final totalW = fits ? constraints.maxWidth : ids.length * colW;

        final content = SizedBox(
          width: totalW,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Zaglavlja kolona (fiksna).
              SizedBox(
                height: headerH,
                child: Row(
                  children: [
                    for (final id in ids)
                      SizedBox(
                        width: colW,
                        child: _boardHeaderCell(id, schedule.barbers[id]),
                      ),
                  ],
                ),
              ),
              // Tijelo: svaka kolona je NEZAVISNA lista svojih slotova, poravnata
              // na vrh — pa smjena svakog barbera počinje odmah od vrha.
              Expanded(
                child: SingleChildScrollView(
                  physics: _schedulePhysics,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final id in ids)
                        SizedBox(
                          width: colW,
                          child: _boardColumn(schedule, id, cellH),
                        ),
                    ],
                  ),
                ),
              ),
              // Footeri kolona (fiksni): broj termina + zarada.
              SizedBox(
                height: footerH,
                child: Row(
                  children: [
                    for (final id in ids)
                      SizedBox(
                        width: colW,
                        child: _boardFooterCell(schedule, id),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );

        if (fits) return content; // sve kolone stanu — bez horizontalnog skrola
        return Scrollbar(
          thumbVisibility: true,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: content,
          ),
        );
      },
    );
  }

  /// Jedna kolona „Pregleda". Zauzeti uzastopni slotovi ISTOG termina se spajaju
  /// u JEDAN blok (tekst se piše jednom, preko cijelog termina), a slobodni
  /// slotovi ostaju pojedinačni (radi izbora za zakazivanje).
  Widget _boardColumn(AllDaySchedule schedule, int barberId, double cellH) {
    final col = schedule.boardColumns[barberId] ?? const <BoardSlot>[];
    if (col.isEmpty) {
      // Barber ne radi tog dana (nema smjene ni termina).
      return SizedBox(
        height: cellH,
        child: Center(
          child:
              Text('—', style: TextStyle(color: Theme.of(context).hintColor)),
        ),
      );
    }

    final timeSize = (cellH * 0.38).clamp(9.0, 18.0).toDouble();

    // Lijeva traka: SATNICA (jedno vrijeme po slotu, uvijek vidljiva).
    final timeStrip = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var k = 0; k < col.length; k++)
          SizedBox(height: cellH, child: _boardTimeCell(col[k], timeSize)),
      ],
    );

    // Desno: spojeni blokovi termina + pojedinačni slobodni slotovi.
    final content = <Widget>[];
    var i = 0;
    while (i < col.length) {
      final entry = col[i].entry;
      if (entry == null) {
        // Slobodan slot — pojedinačan (klik bira slot za zakazivanje).
        content.add(SizedBox(
          height: cellH,
          child: _boardFreeCell(schedule, barberId, i, cellH),
        ));
        i++;
      } else {
        // Spoji sve uzastopne slotove ISTOG termina u jedan blok.
        var j = i + 1;
        while (j < col.length &&
            col[j].entry != null &&
            identical(col[j].entry!.appointment, entry.appointment)) {
          j++;
        }
        final blockH = cellH * (j - i);
        content.add(
            SizedBox(height: blockH, child: _boardBusyCell(entry, blockH)));
        i = j;
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 40, child: timeStrip),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: content,
          ),
        ),
      ],
    );
  }

  /// Jedna ćelija satnice (lijeva traka): vrijeme slota većim fontom; puni sati
  /// podebljani. Uvijek vidljivo, i pored zauzetih blokova.
  Widget _boardTimeCell(BoardSlot slot, double timeSize) {
    final theme = Theme.of(context);
    final isHour = slot.start.minute == 0;
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 6),
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: theme.dividerColor),
          bottom: BorderSide(
            color: isHour
                ? theme.dividerColor
                : theme.dividerColor.withOpacity(0.3),
          ),
        ),
      ),
      child: Text(
        Format.time(slot.start),
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: TextStyle(
          fontSize: timeSize,
          color: isHour ? theme.colorScheme.onSurface : theme.hintColor,
          fontWeight: isHour ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  /// Zaglavlje jedne kolone: boja + ime barbera.
  Widget _boardHeaderCell(int barberId, String? name) {
    final theme = Theme.of(context);
    final color = barberColor(barberId);
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        border: Border(
          right: BorderSide(color: theme.dividerColor),
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              name ?? 'Barber $barberId',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          // Malo dugme: zakaži „vanredni" termin za ovog barbera (sam biraš vrijeme).
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            iconSize: 18,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 26, height: 26),
            tooltip: 'Vanredni termin',
            onPressed: () => _bookExtra(barberId),
          ),
        ],
      ),
    );
  }

  /// Slobodan slot u koloni barbera (pojedinačan): prazan, tap bira slot za
  /// zakazivanje. Kad je izabran — obojen i piše „izabrano" (veći font).
  Widget _boardFreeCell(
      AllDaySchedule schedule, int barberId, int index, double cellH) {
    final theme = Theme.of(context);
    final slot = schedule.boardColumns[barberId]![index];
    final isHour = slot.start.minute == 0;
    final selected = _boardIsSelected(barberId, index);
    final labelSize = (cellH * 0.32).clamp(10.0, 14.0).toDouble();

    return InkWell(
      onTap: () => _onTapBoardFree(schedule, barberId, index),
      child: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primary.withOpacity(0.20) : null,
          border: Border(
            right: BorderSide(color: theme.dividerColor),
            bottom: BorderSide(
              color: isHour
                  ? theme.dividerColor
                  : theme.dividerColor.withOpacity(0.3),
            ),
          ),
        ),
        child: (selected && cellH >= 16)
            ? Text('izabrano',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontSize: labelSize,
                    fontWeight: FontWeight.w600))
            : const SizedBox.shrink(),
      ),
    );
  }

  /// Zauzet BLOK (termin preko svih svojih slotova): boja po statusu; tekst
  /// (ime / telefon / cijena · usluga) ispisan JEDNOM i vertikalno centriran.
  /// Tap otvara promjenu statusa.
  Widget _boardBusyCell(SlotEntry busy, double blockH) {
    final theme = Theme.of(context);
    final status = busy.appointment.status ?? AppointmentStatus.scheduled;
    final bg = busy.isBreak
        ? theme.colorScheme.surfaceContainerHighest
        : switch (status) {
            AppointmentStatus.completed => Colors.green.withOpacity(0.18),
            AppointmentStatus.noShow => Colors.orange.withOpacity(0.18),
            _ => theme.colorScheme.secondaryContainer,
          };
    return InkWell(
      onTap: () => _onTapBusy(
        busy.appointment,
        customerName: busy.customerName,
        customerPhone: busy.customerPhone,
        serviceName: busy.serviceName,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          border: Border(
            right: BorderSide(color: theme.dividerColor),
            bottom: BorderSide(color: theme.dividerColor),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: ClipRect(child: _boardBlockContent(busy, blockH)),
      ),
    );
  }

  /// Sadržaj zauzetog bloka, vertikalno centriran, sa KRUPNIJIM fontom:
  ///   ime klijenta / telefon / cijena · usluga
  /// Font je fiksan (skalira sa zoomom), ne raste sa dužinom termina. Ako je blok
  /// nizak (kratak termin), prikaže manje linija da ne prelije.
  Widget _boardBlockContent(SlotEntry busy, double blockH) {
    final theme = Theme.of(context);
    const lineH = 1.2;
    // Raspoloživa visina (bez paddinga 8 + donjeg okvira 1).
    final avail = blockH - 9;

    // Krupniji font (~2x od ranijeg). Ako ni ime ne bi stalo u nizak blok,
    // srazmjerno ga smanji da bar ime stane.
    var nameSize = 14.4 * _z;
    var subSize = 11.7 * _z;
    if (avail > 0 && nameSize * lineH > avail) {
      final s = avail / (nameSize * lineH);
      nameSize *= s;
      subSize *= s;
    }

    if (busy.isBreak) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Pauza',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontStyle: FontStyle.italic,
            color: theme.hintColor,
            fontSize: nameSize,
            height: lineH,
          ),
        ),
      );
    }

    final name = (busy.customerName?.trim().isNotEmpty ?? false)
        ? busy.customerName!.trim()
        : 'Zauzeto';
    final phone = busy.customerPhone?.trim();

    // „cijena · usluga" (ili samo ono što postoji).
    final price =
        (busy.servicePrice ?? 0) > 0 ? Format.money(busy.servicePrice) : null;
    final service = busy.serviceName?.trim();
    final String? priceService;
    if (price != null && service != null && service.isNotEmpty) {
      priceService = '$price · $service';
    } else {
      priceService =
          price ?? ((service != null && service.isNotEmpty) ? service : null);
    }

    final subStyle =
        TextStyle(fontSize: subSize, color: theme.hintColor, height: lineH);

    // Ime uvijek; telefon i cijena·usluga koliko stane (blok je centriran).
    final lines = <Widget>[
      Text(name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontWeight: FontWeight.w600, fontSize: nameSize, height: lineH)),
    ];
    var remaining = avail - nameSize * lineH;
    final subH = subSize * lineH;
    for (final text in [
      if (phone != null && phone.isNotEmpty) phone,
      if (priceService != null) priceService,
    ]) {
      if (remaining < subH) break;
      lines.add(Text(text,
          maxLines: 1, overflow: TextOverflow.ellipsis, style: subStyle));
      remaining -= subH;
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines,
      ),
    );
  }

  /// Footer jedne kolone: broj termina (i završenih) + zarada od završenih.
  Widget _boardFooterCell(AllDaySchedule schedule, int barberId) {
    final theme = Theme.of(context);
    final t = schedule.totalsByBarber[barberId] ?? const BarberDayTotals();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          right: BorderSide(color: theme.dividerColor),
          top: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${t.appointmentCount} term. (${t.completedCount} zav.)',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          Text(
            Format.money(t.earned),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  /// Jedan red zbirne tabele: vrijeme (lijevo) + linije po barberima (desno).
  Widget _buildAllRow(AllSlot slot) {
    final theme = Theme.of(context);
    final isHour = slot.start.minute == 0; // puni sat — podebljano
    // Prikazujemo termine u SVAKOM pokrivenom slotu (i one koji se nastavljaju
    // iz ranijeg slota), da svi redovi termina budu označeni — tako se vidi
    // trajanje (termin duži od 15 min zauzima više redova).
    final entries = slot.entries;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isHour
                ? theme.dividerColor
                : theme.dividerColor.withOpacity(0.4),
          ),
        ),
      ),
      // IntrinsicHeight => lijeva (vrijeme) i desna ćelija jednake visine,
      // a red raste prema broju barbera u slotu.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Kolona: Vrijeme.
            Container(
              width: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color:
                    theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
                border: Border(right: BorderSide(color: theme.dividerColor)),
              ),
              child: Text(
                Format.time(slot.start),
                style: TextStyle(
                  fontSize: 12,
                  color: isHour ? theme.colorScheme.onSurface : theme.hintColor,
                  fontWeight: isHour ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            // Termini barbera idu JEDAN PORED DRUGOG (dijele širinu).
            // Kad ima više od 2 barbera, sakrijemo ime barbera i uslugu —
            // ostaje samo klijent + telefon (jer su kolone uske).
            Expanded(
              child: entries.isEmpty
                  ? const SizedBox(height: 26)
                  : Builder(builder: (_) {
                      final full = entries.length <= 2;
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < entries.length; i++) ...[
                              if (i > 0) const SizedBox(width: 6),
                              Expanded(
                                child: _entryLine(entries[i], showBarber: full),
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
            ),
          ],
        ),
      ),
    );
  }

  /// Detaljni prikaz: svaki barber dobija svoju kolonu (puni podaci), a kad
  /// ima više barbera tabela se horizontalno skroluje.
  Widget _buildDetailedGrid(AllDaySchedule schedule) {
    final theme = Theme.of(context);

    // Kolone = barberi koji danas imaju bar jedan termin (sortirani po imenu).
    final colMap = <int, String?>{};
    for (final slot in schedule.slots) {
      for (final e in slot.entries) {
        final id = e.employeeId;
        if (id != null && !colMap.containsKey(id)) colMap[id] = e.barberName;
      }
    }
    final columns = colMap.entries.toList()
      ..sort((a, b) => (a.value ?? '').compareTo(b.value ?? ''));

    if (columns.isEmpty) {
      return const EmptyView(
        message: 'Nema zakazanih termina za izabrani dan.',
        icon: Icons.event_available_outlined,
      );
    }

    const timeW = 64.0;
    const minColW = 150.0; // ispod ove širine prelazimo na horizontalni skrol
    final gridRowH = 62.0 * _z; // visina reda (zoom je skalira)
    final headStyle = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 12,
      color: theme.colorScheme.onSurfaceVariant,
    );

    return LayoutBuilder(builder: (context, constraints) {
      final avail = constraints.maxWidth;
      // Ako kolone staju na ekran — rašire se na PUNU širinu (bez skrola).
      // Ako ih je previše — fiksna širina + horizontalni skrol.
      final fits = timeW + columns.length * minColW <= avail;
      final colW = fits ? (avail - timeW) / columns.length : 200.0;
      final totalW = fits ? avail : timeW + columns.length * colW;

      final table = SizedBox(
        width: totalW,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Zaglavlje: vrijeme + ime svakog barbera (sa bojom).
            Container(
              height: 34,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withOpacity(0.5),
                border: Border(bottom: BorderSide(color: theme.dividerColor)),
              ),
              child: Row(
                children: [
                  Container(
                    width: timeW,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border:
                          Border(right: BorderSide(color: theme.dividerColor)),
                    ),
                    child: Text('Vrijeme', style: headStyle),
                  ),
                  for (final c in columns)
                    Container(
                      width: colW,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: barberColor(c.key),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(c.value ?? 'Barber ${c.key}',
                                style: headStyle,
                                overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            // Redovi po slotovima.
            Expanded(
              child: ListView.builder(
                physics: _schedulePhysics,
                itemCount: schedule.slots.length,
                itemExtent: gridRowH,
                itemBuilder: (context, i) =>
                    _buildGridRow(schedule.slots[i], columns, timeW, colW),
              ),
            ),
          ],
        ),
      );

      if (fits) return table; // puna širina, bez skrola
      return Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: table,
        ),
      );
    });
  }

  /// Jedan red detaljne mreže: vrijeme + ćelija po svakom barberu.
  Widget _buildGridRow(AllSlot slot, List<MapEntry<int, String?>> columns,
      double timeW, double colW) {
    final theme = Theme.of(context);
    final isHour = slot.start.minute == 0;
    final byBarber = {for (final e in slot.entries) e.employeeId: e};

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isHour
                ? theme.dividerColor
                : theme.dividerColor.withOpacity(0.4),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Vrijeme.
          Container(
            width: timeW,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color:
                  theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
              border: Border(right: BorderSide(color: theme.dividerColor)),
            ),
            child: Text(
              Format.time(slot.start),
              style: TextStyle(
                fontSize: 12,
                color: isHour ? theme.colorScheme.onSurface : theme.hintColor,
                fontWeight: isHour ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          // Ćelija za svakog barbera (klijent i telefon jedno ispod drugog).
          for (final c in columns)
            SizedBox(
              width: colW,
              child: Padding(
                // Vertikalni odmak prati zoom (da sadržaj uvijek stane u red).
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 3 * _z),
                child: byBarber[c.key] != null
                    ? _gridCell(byBarber[c.key]!)
                    : const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );
  }

  /// Zajednički vertikalni prikaz jednog termina — svaki podatak u svom redu:
  /// ime klijenta, telefon, cijena, pa „vrijeme od – vrijeme do".
  /// Za pauzu prikazuje samo „Pauza". [barberName] (ako je zadat) ide na vrh
  /// (koristi se u zbirnoj listi svih barbera). Veličine fonta su podesive
  /// da bi blok stao u fiksne visine redova (mreža / jedan barber).
  Widget _apptStack({
    required bool isBreak,
    String? name,
    String? phone,
    double? price,
    DateTime? from,
    DateTime? to,
    String? barberName,
    Color? headColor,
    double nameSize = 12.5,
    double subSize = 11,
  }) {
    final theme = Theme.of(context);
    if (isBreak) {
      return Text(
        'Pauza',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontStyle: FontStyle.italic,
          color: theme.hintColor,
          fontSize: nameSize,
        ),
      );
    }

    final clientName = (name != null && name.trim().isNotEmpty)
        ? name.trim()
        : 'Zauzeto';
    final phoneText = phone?.trim();
    final priceText = (price ?? 0) > 0 ? Format.money(price) : null;
    // „08:00 - 08:30" (kraj izračunat iz trajanja ako `to` fali → Format daje —).
    final timeText =
        from != null ? '${Format.time(from)} - ${Format.time(to)}' : null;

    final subStyle =
        TextStyle(fontSize: subSize, color: theme.hintColor, height: 1.1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (barberName != null && barberName.isNotEmpty)
          Text(
            barberName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: headColor,
              fontSize: nameSize,
              height: 1.1,
            ),
          ),
        Text(
          clientName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontWeight: FontWeight.w600, fontSize: nameSize, height: 1.1),
        ),
        if (phoneText != null && phoneText.isNotEmpty)
          Text(phoneText,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: subStyle),
        if (priceText != null)
          Text(priceText,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: subStyle),
        if (timeText != null)
          Text(timeText,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: subStyle),
      ],
    );
  }

  /// Ćelija u mreži: vertikalni blok (ime/telefon/cijena/vrijeme), obojen bojom
  /// barbera. Detalji stoje u SVAKOM pokrivenom polju termina (tako se vidi
  /// koliko traje — svi njegovi redovi su popunjeni).
  Widget _gridCell(SlotEntry e) {
    final color = barberColor(e.employeeId);
    return Container(
      width: double.infinity,
      // Vertikalni odmak prati zoom (da sadržaj uvijek stane u red).
      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2 * _z),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        border: Border(left: BorderSide(color: color, width: 4)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: _apptStack(
        isBreak: e.isBreak,
        name: e.customerName,
        phone: e.customerPhone,
        price: e.servicePrice,
        from: e.startTime,
        to: e.endTime,
        nameSize: 12.5 * _z,
        subSize: 11 * _z,
      ),
    );
  }

  /// Jedan termin u zbirnoj listi svih barbera — vertikalni blok, obojen bojom
  /// barbera. [showBarber] — da li na vrhu prikazati ime barbera (sakrijemo kad
  /// je u redu više barbera pa su kolone uske).
  Widget _entryLine(SlotEntry e, {bool showBarber = true}) {
    final color = barberColor(e.employeeId);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        border: Border(left: BorderSide(color: color, width: 4)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: _apptStack(
        isBreak: e.isBreak,
        name: e.customerName,
        phone: e.customerPhone,
        price: e.servicePrice,
        from: e.startTime,
        to: e.endTime,
        barberName: showBarber ? (e.barberName ?? 'Barber') : null,
        headColor: color,
        nameSize: 12.5 * _z,
        subSize: 11 * _z,
      ),
    );
  }

  Widget _buildTable(DaySchedule schedule) {
    final theme = Theme.of(context);

    // Naznaka rasporeda (radno vrijeme salona + smjena) za ovaj dan/barbera —
    // ovdje je koristimo SAMO za blago sjenčenje redova van smjene. Sam prikaz
    // (radno vrijeme, smjena, upozorenja) je u „Filteri" panelu.
    // `.valueOrNull` → ako još učitava ili endpoint zakaže, jednostavno nema
    // naznake (kalendar radi normalno).
    final info = ref.watch(dayScheduleInfoProvider).valueOrNull;
    final salonClosed =
        info != null && (info.salonOpensAt == null || info.salonClosesAt == null);
    final shiftStartMin = _toMinutes(info?.shiftStart);
    final shiftEndMin = _toMinutes(info?.shiftEnd);

    final slots = schedule.slots;
    final cellH = _rowHeight * _z; // visina jednog slota (zoom skalira)

    // Lijeva kolona: satnica — jedna ćelija po slotu (mreža ostaje).
    // `min` jer smo unutar vertikalnog skrola (neograničena visina).
    final timeStrip = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final s in slots) SizedBox(height: cellH, child: _timeStripCell(s)),
      ],
    );

    // Desna kolona („Klijent"): termin je JEDAN spojen blok preko svih svojih
    // slotova (tekst centriran po sredini), a slobodni slotovi su pojedinačni
    // (klik/izbor za zakazivanje).
    final clientChildren = <Widget>[];
    var i = 0;
    while (i < slots.length) {
      final slot = slots[i];
      if (slot.isBusy) {
        var j = i + 1;
        while (j < slots.length &&
            slots[j].isBusy &&
            identical(slots[j].appointment, slot.appointment)) {
          j++;
        }
        clientChildren
            .add(SizedBox(height: cellH * (j - i), child: _busyBlock(slot)));
        i = j;
      } else {
        clientChildren.add(SizedBox(
          height: cellH,
          child: _freeCell(
            slots,
            i,
            salonClosed: salonClosed,
            shiftStartMin: shiftStartMin,
            shiftEndMin: shiftEndMin,
          ),
        ));
        i++;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _tableHeader(theme),
        Expanded(
          child: SingleChildScrollView(
            physics: _schedulePhysics,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 64, child: timeStrip),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: clientChildren,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Footer: zbir dana (broj termina + zarada od završenih).
        _buildScheduleFooter(theme, schedule),
      ],
    );
  }

  /// Naznaka iznad rasporeda: radno vrijeme salona + smjena barbera za taj dan.
  /// Ako nema podataka (učitava se ili endpoint zakaže), ne prikazuje ništa.
  Widget _buildScheduleBanner(ScheduleDayResponse? info) {
    if (info == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final salonClosed =
        info.salonOpensAt == null || info.salonClosesAt == null;

    final Color bg;
    final IconData icon;
    final lines = <Widget>[];

    if (salonClosed) {
      bg = theme.colorScheme.surfaceContainerHighest;
      icon = Icons.block;
      lines.add(const Text('Salon je zatvoren ovog dana.',
          style: TextStyle(fontWeight: FontWeight.w600)));
    } else {
      bg = theme.colorScheme.primaryContainer.withOpacity(0.35);
      icon = Icons.schedule;
      lines.add(Text(
        'Salon: ${_hhmm(info.salonOpensAt)}–${_hhmm(info.salonClosesAt)}',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ));
      // Smjena barbera za ovaj dan.
      if (info.shiftTemplateId == null) {
        lines.add(Text('Smjena nije dodijeljena — admin treba da izabere.',
            style: TextStyle(color: theme.colorScheme.error)));
      } else if (info.shiftStart == null || info.shiftEnd == null) {
        lines.add(Text('Slobodan dan (barber ne radi).',
            style: TextStyle(color: theme.hintColor)));
      } else {
        final name = (info.shiftTemplateName ?? '').trim();
        lines.add(Text(
          'Smjena: ${_hhmm(info.shiftStart)}–${_hhmm(info.shiftEnd)}'
          '${name.isEmpty ? '' : ' · $name'}',
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ));
      }
    }

    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: lines,
            ),
          ),
        ],
      ),
    );
  }

  /// "HH:mm:ss" → "HH:mm" (ili "—" ako fali).
  String _hhmm(String? t) =>
      (t == null || t.length < 5) ? '—' : t.substring(0, 5);

  /// "HH:mm:ss" → minuti od ponoći (ili null ako fali/neispravno).
  int? _toMinutes(String? t) {
    if (t == null) return null;
    final p = t.split(':');
    if (p.length < 2) return null;
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  /// "YYYY-MM-DD" za dati dan.
  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Provjeri da li je termin u radnom vremenu salona i u smjeni barbera.
  /// Vraća `true` ako jeste (ili ako ne možemo provjeriti). Ako nije — upozori i
  /// pitaj korisnika da li ipak želi da zakaže (backend to dozvoljava).
  Future<bool> _confirmWithinSchedule({
    required int? employeeId,
    required DateTime startLocal,
    required int durationMinutes,
  }) async {
    final day = DateTime(startLocal.year, startLocal.month, startLocal.day);
    ScheduleDayResponse? info;
    try {
      final list = await ref.read(apiServiceProvider).getSchedule(
            employeeId: employeeId,
            from: _ymd(day),
            to: _ymd(day),
          );
      info = list.isNotEmpty ? list.first : null;
    } catch (_) {
      return true; // ne možemo provjeriti → ne blokiramo
    }
    if (info == null) return true;

    final endLocal = startLocal.add(Duration(minutes: durationMinutes));
    final startMin = startLocal.hour * 60 + startLocal.minute;
    final endMin = endLocal.hour * 60 +
        endLocal.minute +
        (endLocal.day != day.day ? 24 * 60 : 0); // ako pređe ponoć

    final problems = <String>[];

    // Radno vrijeme salona. Ako salon NE radi tog dana → TVRDA blokada:
    // ne dozvoljavamo zakazivanje (ne nudimo ni „Zakaži ipak").
    final sOpen = _toMinutes(info.salonOpensAt);
    final sClose = _toMinutes(info.salonClosesAt);
    if (sOpen == null || sClose == null) {
      if (mounted) {
        showSnack(context, 'Salon ne radi ovog dana — zakazivanje nije moguće.',
            isError: true);
      }
      return false;
    }
    if (startMin < sOpen || endMin > sClose) {
      problems.add('termin je van radnog vremena salona '
          '(${_hhmm(info.salonOpensAt)}–${_hhmm(info.salonClosesAt)})');
    }

    // Smjena barbera.
    if (info.shiftTemplateId == null) {
      problems.add('barberu nije dodijeljena smjena');
    } else {
      final shOpen = _toMinutes(info.shiftStart);
      final shClose = _toMinutes(info.shiftEnd);
      if (shOpen == null || shClose == null) {
        problems.add('barber ne radi tog dana');
      } else if (startMin < shOpen || endMin > shClose) {
        problems.add('termin je van smjene barbera '
            '(${_hhmm(info.shiftStart)}–${_hhmm(info.shiftEnd)})');
      }
    }

    if (problems.isEmpty) return true;
    if (!mounted) return false;

    return confirmDialog(
      context,
      title: 'Termin van rasporeda',
      message: 'Upozorenje:\n• ${problems.join('\n• ')}\n\n'
          'Da li ipak želite da zakažete?',
      confirmText: 'Zakaži ipak',
    );
  }

  /// Donja traka rasporeda: koliko termina ima taj dan i koliko je zarađeno
  /// (računa se samo od ZAVRŠENIH termina). Ostaje fiksna ispod tabele.
  Widget _buildScheduleFooter(ThemeData theme, DaySchedule schedule) {
    final numStyle =
        const TextStyle(fontWeight: FontWeight.bold, fontSize: 15);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.event_available_outlined, size: 20),
              const SizedBox(width: 6),
              Text('Termini: ', style: theme.textTheme.bodyMedium),
              Text('${schedule.appointmentCount}', style: numStyle),
              Text('  (završeno ${schedule.completedCount})',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.hintColor)),
              const Spacer(),
              const Icon(Icons.payments_outlined, size: 20),
              const SizedBox(width: 6),
              Text('Zarađeno: ', style: theme.textTheme.bodyMedium),
              Text(Format.money(schedule.earned),
                  style: numStyle.copyWith(color: theme.colorScheme.primary)),
            ],
          ),
        ),
      ),
    );
  }

  /// Zaglavlje tabele (nazivi kolona).
  Widget _tableHeader(ThemeData theme) {
    final headStyle = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 12,
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: theme.dividerColor)),
            ),
            child: Text('Vrijeme', style: headStyle),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Klijent', style: headStyle),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Jedan red tabele (15 min).
  /// Jedna ćelija satnice (lijeva kolona) — vrijeme slota; puni sati podebljani.
  Widget _timeStripCell(ScheduleSlot slot) {
    final theme = Theme.of(context);
    final isHour = slot.start.minute == 0;
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
        border: Border(
          right: BorderSide(color: theme.dividerColor),
          bottom: BorderSide(
            color: isHour
                ? theme.dividerColor
                : theme.dividerColor.withOpacity(0.4),
          ),
        ),
      ),
      child: Text(
        Format.time(slot.start),
        style: TextStyle(
          fontSize: 12,
          color: isHour ? theme.colorScheme.onSurface : theme.hintColor,
          fontWeight: isHour ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  /// SPOJEN blok termina (preko svih svojih slotova): boja po statusu, tekst
  /// (ime/telefon/cijena/vrijeme) ispisan JEDNOM i CENTRIRAN po sredini bloka.
  /// Roditelj (`_buildTable`) mu daje visinu = broj slotova × visina slota.
  Widget _busyBlock(ScheduleSlot slot) {
    final theme = Theme.of(context);
    final appt = slot.appointment!;
    final isBreak = isBreakNote(appt.note);

    final Color bg;
    final Widget content;
    if (isBreak) {
      bg = theme.colorScheme.surfaceContainerHighest;
      content = Row(
        children: [
          Icon(Icons.free_breakfast_outlined, size: 16, color: theme.hintColor),
          const SizedBox(width: 6),
          Text('Pauza',
              style: TextStyle(
                  fontStyle: FontStyle.italic, color: theme.hintColor)),
        ],
      );
    } else {
      final status = appt.status ?? AppointmentStatus.scheduled;
      bg = switch (status) {
        AppointmentStatus.completed => Colors.green.withOpacity(0.18),
        AppointmentStatus.noShow => Colors.orange.withOpacity(0.18),
        _ => theme.colorScheme.secondaryContainer,
      };
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: _apptStack(
              isBreak: false,
              name: slot.customerName,
              phone: slot.customerPhone,
              price: appt.servicePrice,
              from: appt.startTime,
              to: appt.endTime,
              nameSize: 12 * _z,
              subSize: 10 * _z,
            ),
          ),
          if (status != AppointmentStatus.scheduled) _statusBadge(status),
        ],
      );
    }

    return InkWell(
      onTap: () => _onTapBusy(
        appt,
        customerName: slot.customerName,
        customerPhone: slot.customerPhone,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          border: Border(bottom: BorderSide(color: theme.dividerColor)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.centerLeft, // vertikalno centrira preko cijelog bloka
        child: content,
      ),
    );
  }

  /// Jedna SLOBODNA ćelija (jedan slot): klik bira slot za zakazivanje;
  /// van smjene/zatvoren salon blago zasjenčeni; „izabrano" kad je u izboru.
  Widget _freeCell(
    List<ScheduleSlot> slots,
    int index, {
    bool salonClosed = false,
    int? shiftStartMin,
    int? shiftEndMin,
  }) {
    final theme = Theme.of(context);
    final slot = slots[index];
    final selected = _isSelected(index);
    final isHour = slot.start.minute == 0;

    Color? bg;
    Widget content = const SizedBox.shrink();
    if (selected) {
      bg = theme.colorScheme.primary.withOpacity(0.20);
      content = Text('izabrano',
          style:
              TextStyle(color: theme.colorScheme.primary, fontSize: 12 * _z));
    } else {
      final slotMin = slot.start.hour * 60 + slot.start.minute;
      final outsideShift = shiftStartMin != null &&
          shiftEndMin != null &&
          (slotMin < shiftStartMin || slotMin >= shiftEndMin);
      if (salonClosed || outsideShift) {
        bg = theme.colorScheme.surfaceContainerHighest.withOpacity(0.5);
      }
    }

    return InkWell(
      onTap: () => _onTapFree(slots, index),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          border: Border(
            bottom: BorderSide(
              color: isHour
                  ? theme.dividerColor
                  : theme.dividerColor.withOpacity(0.4),
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.centerLeft,
        child: content,
      ),
    );
  }
}
