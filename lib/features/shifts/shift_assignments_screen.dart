import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // HardwareKeyboard (Ctrl+klik)
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/exceptions.dart';
import '../../models/models.dart';
import '../../services/providers.dart';
import '../../shared/month_picker.dart';
import '../../shared/widgets.dart';
import '../employees/employees_provider.dart';
import 'shift_assignments_provider.dart' show allShiftTemplatesProvider, ymd;
import 'shift_days_provider.dart';

// ------------------------------ Pomoćne funkcije ------------------------------
// (Mjesečni birač i nazivi mjeseci su u ../../shared/month_picker.dart.)

/// "HH:mm:ss" → "HH:mm" (za prikaz u ćeliji).
String _hm(String? hhmmss) {
  if (hhmmss == null) return '';
  final p = hhmmss.split(':');
  return p.length < 2 ? hhmmss : '${p[0]}:${p[1]}';
}

/// `TimeOfDay` → "HH:mm:ss" (format za server).
String _apiTime(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

/// "HH:mm:ss" → `TimeOfDay` (ili rezerva).
TimeOfDay _parseTime(String? hhmmss, TimeOfDay fallback) {
  if (hhmmss == null) return fallback;
  final p = hhmmss.split(':');
  if (p.length < 2) return fallback;
  final h = int.tryParse(p[0]), m = int.tryParse(p[1]);
  if (h == null || m == null) return fallback;
  return TimeOfDay(hour: h, minute: m);
}

int _mins(TimeOfDay t) => t.hour * 60 + t.minute;

/// Reprezentativni sati šablona (prvi dan koji ima definisano vrijeme).
({TimeOfDay start, TimeOfDay end})? _templateHours(ShiftTemplateResponse t) {
  for (final d in t.days) {
    if (d.startTime != null && d.endTime != null) {
      return (
        start: _parseTime(d.startTime, const TimeOfDay(hour: 8, minute: 0)),
        end: _parseTime(d.endTime, const TimeOfDay(hour: 14, minute: 0)),
      );
    }
  }
  return null;
}

// ================================== EKRAN ==================================

/// Ekran „Dodjela smjena" (ADMIN): mjesečni kalendar. Gore mjesec, lijevo lista
/// barbera, ostatak je veliki kalendar. Izabereš barbera → čekiraš dane →
/// „Dodijeli smjenu" bira smjenu za te dane. Izmjena/uklanjanje po danu.
class ShiftAssignmentsScreen extends ConsumerWidget {
  const ShiftAssignmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasError = ref.watch(
        shiftDaysControllerProvider.select((s) => s.error));

    return Column(
      children: [
        const _MonthBar(),
        if (hasError != null) const _BackendNotice(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              // Široko (desktop/tablet): barberi lijevo, kalendar desno.
              if (c.maxWidth >= 720) {
                return const Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 220, child: _BarberPanel()),
                    VerticalDivider(width: 1),
                    Expanded(child: _MonthCalendar()),
                  ],
                );
              }
              // Usko (telefon): barberi kao traka gore, kalendar ispod.
              return const Column(
                children: [
                  _BarberStrip(),
                  Divider(height: 1),
                  Expanded(child: _MonthCalendar()),
                ],
              );
            },
          ),
        ),
        const _ActionBar(),
      ],
    );
  }
}

/// Gornja traka: ‹ Mjesec Godina › (klik na naziv otvara izbor mjeseca).
class _MonthBar extends ConsumerWidget {
  const _MonthBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(shiftDaysControllerProvider.select((s) => s.month));
    final ctrl = ref.read(shiftDaysControllerProvider.notifier);

    return Material(
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Prethodni mjesec',
              onPressed: () => ctrl.shiftMonth(-1),
            ),
            Expanded(
              child: Center(
                child: TextButton.icon(
                  icon: const Icon(Icons.calendar_month, size: 18),
                  label: Text(
                    monthLabel(month),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  onPressed: () async {
                    final picked = await showMonthPicker(context, month);
                    if (picked != null) ctrl.setMonth(picked);
                  },
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Sljedeći mjesec',
              onPressed: () => ctrl.shiftMonth(1),
            ),
          ],
        ),
      ),
    );
  }
}

/// Blaga poruka kad backend za smjene po danu još nije spreman (ne ruši ekran).
class _BackendNotice extends StatelessWidget {
  const _BackendNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.5),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Smjene se ne mogu učitati/sačuvati — backend za dodjelu po danu '
              'još nije spreman.',
              style: theme.textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Lijeva (uska) lista barbera — na širokom ekranu.
class _BarberPanel extends ConsumerWidget {
  const _BarberPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(employeesProvider);
    final selected =
        ref.watch(shiftDaysControllerProvider.select((s) => s.selectedEmployeeId));
    final ctrl = ref.read(shiftDaysControllerProvider.notifier);

    return async.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(
        message: ApiException.from(e).message,
        onRetry: () => ref.invalidate(employeesProvider),
      ),
      data: (emps) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Text('Barberi',
                style: Theme.of(context).textTheme.titleSmall),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                for (final e in emps)
                  ListTile(
                    dense: true,
                    selected: e.id == selected,
                    leading: CircleAvatar(
                      radius: 16,
                      child: Text((e.name?.isNotEmpty ?? false)
                          ? e.name![0].toUpperCase()
                          : '?'),
                    ),
                    title: Text(e.name ?? 'Zaposleni ${e.id}',
                        overflow: TextOverflow.ellipsis),
                    trailing: e.id == selected
                        ? const Icon(Icons.check_circle, size: 18)
                        : null,
                    onTap: () => ctrl.selectEmployee(e.id),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Traka barbera (čipovi) — na uskom ekranu (telefon).
class _BarberStrip extends ConsumerWidget {
  const _BarberStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(employeesProvider);
    final selected =
        ref.watch(shiftDaysControllerProvider.select((s) => s.selectedEmployeeId));
    final ctrl = ref.read(shiftDaysControllerProvider.notifier);

    return SizedBox(
      height: 56,
      child: async.when(
        loading: () => const Center(
            child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))),
        error: (e, _) => Center(
            child: Text(ApiException.from(e).message,
                style: TextStyle(color: Theme.of(context).colorScheme.error))),
        data: (emps) => ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          children: [
            for (final e in emps)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(e.name ?? 'Zaposleni ${e.id}'),
                  selected: e.id == selected,
                  onSelected: (_) => ctrl.selectEmployee(e.id),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Veliki mjesečni kalendar (7 kolona × sedmice), ćelije se čekiraju.
class _MonthCalendar extends ConsumerWidget {
  const _MonthCalendar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(shiftDaysControllerProvider);
    final ctrl = ref.read(shiftDaysControllerProvider.notifier);
    final month = state.month;

    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = DateTime(month.year, month.month, 1).weekday - 1; // Pon=1
    final weeks = ((leading + daysInMonth) / 7).ceil();

    // Ćelije: null za prazna polja (prije 1. i poslije zadnjeg dana mjeseca).
    final cells = <DateTime?>[
      for (var i = 0; i < weeks * 7; i++)
        (i - leading + 1) >= 1 && (i - leading + 1) <= daysInMonth
            ? DateTime(month.year, month.month, i - leading + 1)
            : null,
    ];

    void onTapDay(DateTime date) {
      if (state.selectedEmployeeId == null) {
        showSnack(context, 'Prvo izaberi barbera.', isError: true);
        return;
      }
      final day = ymd(date);
      // Ctrl+klik → izaberi opseg od zadnjeg kliknutog dana; inače običan izbor.
      if (HardwareKeyboard.instance.isControlPressed) {
        ctrl.selectRange(day);
      } else {
        ctrl.toggleDay(day);
      }
    }

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          // Zaglavlje: skraćeni nazivi dana (Pon..Ned).
          Row(
            children: [
              for (final d in WeekDay.values)
                Expanded(
                  child: Center(
                    child: Text(d.shortLabel,
                        style: Theme.of(context).textTheme.labelSmall),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Column(
              children: [
                for (var w = 0; w < weeks; w++)
                  Expanded(
                    child: Row(
                      children: [
                        for (var i = 0; i < 7; i++)
                          Expanded(
                            child: _DayCell(
                              date: cells[w * 7 + i],
                              shift: cells[w * 7 + i] == null ||
                                      state.selectedEmployeeId == null
                                  ? null
                                  : state.shiftFor(state.selectedEmployeeId!,
                                      ymd(cells[w * 7 + i]!)),
                              selected: cells[w * 7 + i] != null &&
                                  state.selectedDays
                                      .contains(ymd(cells[w * 7 + i]!)),
                              onTap: cells[w * 7 + i] == null
                                  ? null
                                  : () => onTapDay(cells[w * 7 + i]!),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Jedna ćelija kalendara: broj dana + smjena (ako je ima) + oznaka izbora.
class _DayCell extends StatelessWidget {
  final DateTime? date;
  final ShiftDayResponse? shift;
  final bool selected;
  final VoidCallback? onTap;

  const _DayCell({
    required this.date,
    required this.shift,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Prazno polje (drugi mjesec).
    if (date == null) {
      return Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
      );
    }

    final hasShift = shift != null;
    final isOff = shift?.off ?? false; // slobodan dan (zaposleni ne radi)
    final bg = selected
        ? cs.primary.withValues(alpha: 0.18)
        : isOff
            ? cs.surfaceContainerHighest.withValues(alpha: 0.8)
            : hasShift
                ? cs.primaryContainer.withValues(alpha: 0.5)
                : cs.surface;
    final borderColor = selected ? cs.primary : cs.outlineVariant;

    // Za slobodan dan pišemo „Slobodan"; inače naziv šablona ili vrijeme smjene.
    final label = isOff
        ? 'Slobodan'
        : hasShift
            ? (shift!.shiftTemplateName?.isNotEmpty ?? false
                ? shift!.shiftTemplateName!
                : '${_hm(shift!.startTime)}–${_hm(shift!.endTime)}')
            : null;
    final labelColor = isOff ? cs.onSurfaceVariant : cs.onPrimaryContainer;

    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: borderColor, width: selected ? 2 : 1),
            ),
            padding: const EdgeInsets.all(4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('${date!.day}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12)),
                    const Spacer(),
                    if (selected)
                      Icon(Icons.check_circle, size: 14, color: cs.primary),
                  ],
                ),
                const Spacer(),
                if (label != null)
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        color: labelColor,
                        fontStyle: isOff ? FontStyle.italic : FontStyle.normal,
                        fontWeight: FontWeight.w500),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Donja traka: koliko dana izabrano + „Ukloni" / „Dodijeli smjenu".
class _ActionBar extends ConsumerWidget {
  const _ActionBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(shiftDaysControllerProvider);
    final empId = state.selectedEmployeeId;
    final isAdmin = ref.watch(authControllerProvider).isAdmin;

    // Zaposleni (ne-admin) vidi dodjelu smjena samo za pregled — bez akcija.
    if (!isAdmin) {
      return const Material(
        elevation: 8,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: ReadOnlyBanner(),
          ),
        ),
      );
    }

    // Ime aktivnog barbera (za lijepšu poruku).
    final name = ref.watch(employeesProvider).maybeWhen(
          data: (emps) {
            final match = emps.where((e) => e.id == empId);
            return match.isEmpty ? null : match.first.name;
          },
          orElse: () => null,
        );

    final theme = Theme.of(context);
    final count = state.selectedDays.length;

    String message;
    if (empId == null) {
      message = 'Izaberi barbera, pa čekiraj dane (Ctrl+klik = opseg).';
    } else if (count == 0) {
      message = '${name ?? 'Barber'}: čekiraj dane (Ctrl+klik = opseg).';
    } else {
      message = '${name ?? 'Barber'} — izabrano dana: $count';
    }

    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          // Bez barbera: samo kratka uputa. Sa barberom: poruka + dugmad koja se
          // (na uskom ekranu) prelome u novi red umjesto da „iscure".
          child: empId == null
              ? Text(message, style: theme.textTheme.bodyMedium)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      message,
                      style: theme.textTheme.bodyMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed:
                              count == 0 ? null : () => _remove(context, ref),
                          icon: const Icon(Icons.remove_circle_outline,
                              size: 18),
                          label: const Text('Ukloni'),
                        ),
                        OutlinedButton.icon(
                          onPressed:
                              count == 0 ? null : () => _dayOff(context, ref),
                          icon: const Icon(Icons.event_busy, size: 18),
                          label: const Text('Slobodan dan'),
                        ),
                        FilledButton.icon(
                          onPressed:
                              count == 0 ? null : () => _assign(context, ref),
                          icon: const Icon(Icons.event_available, size: 18),
                          label: const Text('Dodijeli smjenu'),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _assign(BuildContext context, WidgetRef ref) async {
    final state = ref.read(shiftDaysControllerProvider);
    final ctrl = ref.read(shiftDaysControllerProvider.notifier);
    final empId = state.selectedEmployeeId;
    if (empId == null || state.selectedDays.isEmpty) return;

    final choice = await showDialog<_ShiftChoice>(
      context: context,
      builder: (_) => const _AssignShiftDialog(),
    );
    if (choice == null) return;

    final requests = [
      for (final day in state.selectedDays)
        ShiftDayRequest(
          employeeId: empId,
          date: day,
          startTime: choice.startTime,
          endTime: choice.endTime,
          shiftTemplateId: choice.templateId,
        ),
    ];
    try {
      await ctrl.assign(requests);
      if (context.mounted) {
        showSnack(context, 'Smjena dodijeljena (${requests.length} dana).');
      }
    } catch (e) {
      if (context.mounted) {
        showSnack(context, ApiException.from(e).message, isError: true);
      }
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: 'Ukloni smjenu',
      message: 'Ukloniti smjenu za izabrane dane?',
      confirmText: 'Ukloni',
    );
    if (!ok) return;
    final ctrl = ref.read(shiftDaysControllerProvider.notifier);
    try {
      await ctrl.removeSelectedDays();
      if (context.mounted) showSnack(context, 'Smjena uklonjena.');
    } catch (e) {
      if (context.mounted) {
        showSnack(context, ApiException.from(e).message, isError: true);
      }
    }
  }

  /// Označi izabrane dane kao „slobodan dan": zaposleni tada ne radi i nema
  /// smjenu (backend za takav dan vraća prazan raspored — ne može se zakazati).
  Future<void> _dayOff(BuildContext context, WidgetRef ref) async {
    final state = ref.read(shiftDaysControllerProvider);
    final ctrl = ref.read(shiftDaysControllerProvider.notifier);
    final empId = state.selectedEmployeeId;
    if (empId == null || state.selectedDays.isEmpty) return;

    final ok = await confirmDialog(
      context,
      title: 'Slobodan dan',
      message:
          'Označiti izabrane dane kao slobodne? Zaposleni tada ne radi i nema '
          'smjenu za te dane.',
      confirmText: 'Slobodan dan',
    );
    if (!ok) return;

    // Za slobodan dan šaljemo off=true (bez vremena) — po jedan zahtjev za dan.
    final requests = [
      for (final day in state.selectedDays)
        ShiftDayRequest(employeeId: empId, date: day, off: true),
    ];
    try {
      await ctrl.assign(requests);
      if (context.mounted) {
        showSnack(context, 'Označeno kao slobodan dan (${requests.length}).');
      }
    } catch (e) {
      if (context.mounted) {
        showSnack(context, ApiException.from(e).message, isError: true);
      }
    }
  }
}

/// Rezultat dijaloga za dodjelu: vrijeme (za server) + opciono id šablona.
class _ShiftChoice {
  final String startTime; // "HH:mm:ss"
  final String endTime;
  final int? templateId;
  const _ShiftChoice(this.startTime, this.endTime, this.templateId);
}

/// Dijalog: izbor smjene za dodjelu. Može se izabrati šablon (popuni vrijeme)
/// ili unijeti proizvoljno vrijeme.
class _AssignShiftDialog extends ConsumerStatefulWidget {
  const _AssignShiftDialog();

  @override
  ConsumerState<_AssignShiftDialog> createState() => _AssignShiftDialogState();
}

class _AssignShiftDialogState extends ConsumerState<_AssignShiftDialog> {
  int? _templateId;
  TimeOfDay _start = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 14, minute: 0);

  Future<TimeOfDay?> _pick(TimeOfDay initial) => showTimePicker(
        context: context,
        initialTime: initial,
        initialEntryMode: TimePickerEntryMode.input, // po difoltu unos brojki
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        ),
      );

  void _save() {
    if (_mins(_end) <= _mins(_start)) {
      showSnack(context, 'Kraj mora biti poslije početka.', isError: true);
      return;
    }
    Navigator.of(context).pop(
      _ShiftChoice(_apiTime(_start), _apiTime(_end), _templateId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final templatesAsync = ref.watch(allShiftTemplatesProvider);

    return AlertDialog(
      title: const Text('Dodijeli smjenu'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Izbor šablona (opciono) — popuni vrijeme iz šablona.
            templatesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => const SizedBox.shrink(),
              data: (templates) => DropdownButtonFormField<int?>(
                value: _templateId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Šablon smjene (opciono)',
                  prefixIcon: Icon(Icons.calendar_view_week),
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text('Proizvoljno vrijeme')),
                  for (final t in templates)
                    DropdownMenuItem(
                        value: t.id, child: Text(t.name ?? 'Šablon ${t.id}')),
                ],
                onChanged: (v) {
                  setState(() {
                    _templateId = v;
                    // Popuni vrijeme iz izabranog šablona (ako ga ima).
                    final t = templates.where((x) => x.id == v);
                    if (t.isNotEmpty) {
                      final hours = _templateHours(t.first);
                      if (hours != null) {
                        _start = hours.start;
                        _end = hours.end;
                      }
                    }
                  });
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                    child: _timeField('Početak', _start,
                        (t) => setState(() => _start = t))),
                const SizedBox(width: 8),
                Expanded(
                    child: _timeField(
                        'Kraj', _end, (t) => setState(() => _end = t))),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Otkaži')),
        FilledButton(onPressed: _save, child: const Text('Sačuvaj')),
      ],
    );
  }

  Widget _timeField(
      String label, TimeOfDay value, ValueChanged<TimeOfDay> onPicked) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: Theme.of(context).hintColor)),
        const SizedBox(height: 2),
        OutlinedButton.icon(
          icon: const Icon(Icons.schedule, size: 18),
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          onPressed: () async {
            final picked = await _pick(value);
            if (picked != null) onPicked(picked);
          },
          label: Text(_hm(_apiTime(value))),
        ),
      ],
    );
  }
}
