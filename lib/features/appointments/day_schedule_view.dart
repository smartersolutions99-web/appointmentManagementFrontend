import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/exceptions.dart';
import '../../models/models.dart';
import '../../services/providers.dart';
import '../../shared/format.dart';
import '../../shared/widgets.dart';
import '../employees/employees_provider.dart';
import '../services/services_provider.dart';
import 'appointment_search_screen.dart';
import 'barber_colors.dart';
import 'day_schedule_provider.dart';
import 'slot_booking_form.dart';

/// Dnevni raspored kao tabela: redovi su slotovi od 15 minuta.
/// Lijeva kolona je vrijeme, desna pokazuje klijenta (ako je zauzeto).
/// Slobodna polja se biraju (od–do), pa se zakazuje preko dugmeta.
class DayScheduleView extends ConsumerStatefulWidget {
  const DayScheduleView({super.key});

  @override
  ConsumerState<DayScheduleView> createState() => _DayScheduleViewState();
}

class _DayScheduleViewState extends ConsumerState<DayScheduleView> {
  // Visina jednog reda — fiksna, pa je ListView brži i tabela urednija.
  static const double _rowHeight = 34;

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

  /// Tap na slobodan slot: prvi = početak, drugi = kraj (opseg).
  void _onTapFree(List<ScheduleSlot> slots, int index) {
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

  Future<void> _book(DaySchedule schedule) async {
    final lo = _lo, hi = _hi;
    if (lo == null || hi == null) return;

    final start = schedule.slots[lo].start;
    final duration = (hi - lo + 1) * kSlotMinutes;

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
    if (!mounted) return;

    final request = await showSlotBookingForm(
      context,
      startTime: start,
      durationMinutes: duration,
      employeeId: schedule.employeeId,
      services: services,
    );
    if (request == null) return;

    // Provjeri da li telefon već postoji pod drugim imenom (i pitaj korisnika).
    final resolved = await _resolveCustomerConflict(request);
    if (resolved == null) return; // korisnik otkazao

    try {
      await ref.read(apiServiceProvider).createAppointment(resolved);
      _clearSelection();
      ref.invalidate(dayScheduleProvider);
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
    final duration = (hi - lo + 1) * kSlotMinutes;

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
      ref.invalidate(dayScheduleProvider);
      if (mounted) showSnack(context, 'Pauza dodata.');
    } catch (e) {
      if (mounted) {
        showSnack(context, ApiException.from(e).message, isError: true);
      }
    }
  }

  /// Tap na zauzet slot: pauza → ponudi uklanjanje; termin → promjena statusa.
  Future<void> _onTapBusy(AppointmentResponse appt) async {
    if (isBreakNote(appt.note)) {
      await _removeBreak(appt);
    } else {
      await _changeStatus(appt);
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
      ref.invalidate(dayScheduleProvider);
      if (mounted) showSnack(context, 'Pauza uklonjena.');
    } catch (e) {
      if (mounted) {
        showSnack(context, ApiException.from(e).message, isError: true);
      }
    }
  }

  /// Promjena statusa termina (Zakazan/Završen/Otkazan/Nije se pojavio).
  Future<void> _changeStatus(AppointmentResponse appt) async {
    final id = appt.id;
    if (id == null) return;

    final selected = await showModalBottomSheet<AppointmentStatus>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Status termina',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
          ],
        ),
      ),
    );

    if (selected == null || selected == appt.status) return;
    try {
      await ref
          .read(apiServiceProvider)
          .changeAppointmentStatus(id, StatusChangeRequest(status: selected));
      ref.invalidate(dayScheduleProvider);
      if (mounted) showSnack(context, 'Status: ${selected.label}.');
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

  /// Gornja traka: prethodni/sljedeći dan, datum (kalendar) i pretraga.
  Widget _buildToolbar() {
    final date = ref.watch(scheduleDateProvider);
    final theme = Theme.of(context);

    // Naziv dana pored datuma; za današnji dan piše „Danas".
    final now = DateTime.now();
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;
    final dayLabel = isToday ? 'Danas' : Format.weekday(date);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Prethodni dan',
              onPressed: () => _shiftDay(-1),
            ),
            Expanded(
              child: TextButton.icon(
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text('$dayLabel, ${Format.date(date)}'),
                onPressed: _pickDate,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Sljedeći dan',
              onPressed: () => _shiftDay(1),
            ),
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Pretraga klijenta',
              onPressed: _openSearch,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    // Admin može da uključi agenda prikaz svih barbera.
    final showAll = auth.isAdmin && ref.watch(scheduleShowAllProvider);
    final scheduleAsync = ref.watch(dayScheduleProvider);

    final lo = _lo, hi = _hi;
    final minutes = (lo != null && hi != null) ? (hi - lo + 1) * kSlotMinutes : 0;

    return Scaffold(
      // Dugme za zakazivanje ima smisla samo u prikazu rasporeda jednog barbera.
      floatingActionButton: (!showAll && lo != null && scheduleAsync.hasValue)
          ? Row(
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
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildToolbar(),
          // Kad admin gleda jednog barbera — dugme za povratak na sve barbere.
          if (auth.isAdmin && !showAll) _buildBackToAllBar(),
          Expanded(
            child: showAll
                ? _buildAllTable()
                : AsyncValueView<DaySchedule>(
                    value: scheduleAsync,
                    onRetry: () => ref.invalidate(dayScheduleProvider),
                    data: _buildTable,
                  ),
          ),
        ],
      ),
    );
  }

  // Izaberi jednog barbera (iz legende) → prikaži samo njegov raspored.
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

  /// Traka iznad rasporeda jednog barbera: dugme za povratak na sve barbere.
  Widget _buildBackToAllBar() {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: _showAllBarbers,
        icon: const Icon(Icons.arrow_back),
        label: const Text('Svi barberi'),
      ),
    );
  }

  // ===================== ZBIRNA TABELA: SVI BARBERI =====================

  /// Zbirna tabela: ista mreža kao za jednog barbera, ali svaki slot prikazuje
  /// sve barbere koji tu počinju (barber — klijent · telefon · usluga).
  Widget _buildAllTable() {
    final scheduleAsync = ref.watch(allDayScheduleProvider);
    return AsyncValueView<AllDaySchedule>(
      value: scheduleAsync,
      onRetry: () => ref.invalidate(allDayScheduleProvider),
      data: (schedule) {
        final theme = Theme.of(context);
        final detailed = ref.watch(scheduleDetailedProvider);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Naslov dana + switch za detaljni prikaz.
            Container(
              color: theme.colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Svi barberi — ${Format.date(schedule.day)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Text('Detaljno'),
                  Switch(
                    value: detailed,
                    onChanged: (v) => ref
                        .read(scheduleDetailedProvider.notifier)
                        .state = v,
                  ),
                ],
              ),
            ),
            _buildLegend(schedule.barbers),
            if (detailed)
              Expanded(child: _buildDetailedGrid(schedule))
            else ...[
              _tableHeader(theme),
              Expanded(
                child: ListView.builder(
                  itemCount: schedule.slots.length,
                  itemBuilder: (context, i) => _buildAllRow(schedule.slots[i]),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  /// Legenda: klikabilni čipovi barbera. Klik na barbera otvara samo njegov
  /// raspored (gdje je moguće i zakazati novi termin).
  Widget _buildLegend(Map<int, String?> barbers) {
    if (barbers.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Klikni na barbera za njegov raspored:',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in barbers.entries)
                ActionChip(
                  avatar: CircleAvatar(
                    backgroundColor: barberColor(entry.key),
                    radius: 7,
                  ),
                  label: Text(entry.value ?? 'Barber ${entry.key}'),
                  onPressed: () => _selectBarber(entry.key),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Jedan red zbirne tabele: vrijeme (lijevo) + linije po barberima (desno).
  Widget _buildAllRow(AllSlot slot) {
    final theme = Theme.of(context);
    final isHour = slot.start.minute == 0; // puni sat — podebljano

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
              child: slot.entries.isEmpty
                  ? const SizedBox(height: 26)
                  : Builder(builder: (_) {
                      final full = slot.entries.length <= 2;
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < slot.entries.length; i++) ...[
                              if (i > 0) const SizedBox(width: 6),
                              Expanded(
                                child: _entryLine(slot.entries[i],
                                    showBarber: full, showService: full),
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
    const gridRowH = 46.0;
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                child: byBarber[c.key] != null
                    ? _gridCell(byBarber[c.key]!)
                    : const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );
  }

  /// Ćelija u mreži: klijent (podebljano) i telefon ispod njega, obojeno bojom
  /// barbera. Za pauzu piše „Pauza".
  Widget _gridCell(SlotEntry e) {
    final theme = Theme.of(context);
    final color = barberColor(e.employeeId);
    final lines = e.isBreak
        ? <String>['Pauza']
        : [
            if (e.customerName?.trim().isNotEmpty ?? false)
              e.customerName!.trim(),
            if (e.customerPhone?.trim().isNotEmpty ?? false)
              e.customerPhone!.trim(),
          ];
    if (lines.isEmpty) lines.add('Zauzeto');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        border: Border(left: BorderSide(color: color, width: 4)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < lines.length; i++)
            Text(
              lines[i],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: i == 0 ? 12.5 : 11,
                fontWeight: i == 0 ? FontWeight.w600 : FontWeight.normal,
                color: i == 0 ? null : theme.hintColor,
              ),
            ),
        ],
      ),
    );
  }

  /// Jedna linija u slotu — obojena bojom barbera.
  /// [showBarber] — da li prikazati ime barbera (sakrijemo kad je gužva).
  /// [showService] — da li prikazati naziv usluge.
  Widget _entryLine(SlotEntry e,
      {bool showBarber = true, bool showService = true}) {
    final color = barberColor(e.employeeId);
    final parts = e.isBreak
        ? <String>['Pauza']
        : [e.customerName, e.customerPhone, if (showService) e.serviceName]
            .where((s) => s != null && s.isNotEmpty)
            .cast<String>()
            .toList();
    final detail = parts.join('  ·  ');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        border: Border(left: BorderSide(color: color, width: 4)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: showBarber
          ? Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: e.barberName ?? 'Barber',
                    style: TextStyle(fontWeight: FontWeight.bold, color: color),
                  ),
                  if (detail.isNotEmpty) TextSpan(text: '  —  $detail'),
                ],
              ),
              style: const TextStyle(fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : Text(
              detail.isEmpty ? 'Zauzeto' : detail,
              style: const TextStyle(fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
    );
  }

  Widget _buildTable(DaySchedule schedule) {
    final theme = Theme.of(context);
    final auth = ref.watch(authControllerProvider);

    // Za admina prikazujemo i ime barbera čiji se raspored gleda.
    String? barberName;
    if (auth.isAdmin && schedule.employeeId != null) {
      final employees = ref.watch(employeesProvider).valueOrNull;
      if (employees != null) {
        for (final e in employees) {
          if (e.id == schedule.employeeId) {
            barberName = e.name;
            break;
          }
        }
      }
    }

    final title = barberName != null
        ? 'Raspored: $barberName — ${Format.date(schedule.day)}'
        : 'Raspored — ${Format.date(schedule.day)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Naslov dana (za admina i ime barbera).
        Container(
          color: theme.colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        _tableHeader(theme),
        Expanded(
          child: ListView.builder(
            itemCount: schedule.slots.length,
            itemExtent: _rowHeight, // fiksna visina reda
            itemBuilder: (context, index) => _buildRow(schedule.slots, index),
          ),
        ),
      ],
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
  Widget _buildRow(List<ScheduleSlot> slots, int index) {
    final slot = slots[index];
    final theme = Theme.of(context);
    final selected = _isSelected(index);
    final isHour = slot.start.minute == 0; // puni sat — podebljano

    // Desna ćelija (Klijent): boja i sadržaj zavise od stanja slota.
    Color? contentBg;
    Widget content = const SizedBox.shrink();
    if (slot.isBusy) {
      final appt = slot.appointment!;
      final isBreak = isBreakNote(appt.note);
      if (isBreak) {
        // Pauza — neutralna boja i oznaka „Pauza“ u svakom polju.
        contentBg = theme.colorScheme.surfaceContainerHighest;
        content = Row(
          children: [
            Icon(Icons.free_breakfast_outlined,
                size: 16, color: theme.hintColor),
            const SizedBox(width: 6),
            Text('Pauza',
                style: TextStyle(
                    fontStyle: FontStyle.italic, color: theme.hintColor)),
          ],
        );
      } else {
        // Termin — boja prema statusu, sa imenom klijenta i bedžom statusa.
        final status = appt.status ?? AppointmentStatus.scheduled;
        contentBg = switch (status) {
          AppointmentStatus.completed => Colors.green.withOpacity(0.18),
          AppointmentStatus.noShow => Colors.orange.withOpacity(0.18),
          _ => theme.colorScheme.secondaryContainer,
        };
        // Ime + telefon u SVAKOM polju termina (isto kao prvo polje).
        final label = [slot.customerName, slot.customerPhone]
            .where((s) => s != null && s.isNotEmpty)
            .join('  ·  ');
        content = Row(
          children: [
            Expanded(
              child: Text(
                label.isEmpty ? 'Zauzeto' : label,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (status != AppointmentStatus.scheduled) _statusBadge(status),
          ],
        );
      }
    } else if (selected) {
      contentBg = theme.colorScheme.primary.withOpacity(0.20);
      content = Text('izabrano',
          style: TextStyle(color: theme.colorScheme.primary, fontSize: 12));
    }

    return InkWell(
      onTap: slot.isBusy
          ? () => _onTapBusy(slot.appointment!)
          : () => _onTapFree(slots, index),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isHour
                  ? theme.dividerColor
                  : theme.dividerColor.withOpacity(0.4),
            ),
          ),
        ),
        // stretch => obje ćelije popune visinu reda (linije do kraja).
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
            // Kolona: Klijent.
            Expanded(
              child: Container(
                color: contentBg,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.centerLeft,
                child: content,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
