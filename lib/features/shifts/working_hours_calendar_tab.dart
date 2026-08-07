import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // HardwareKeyboard (Ctrl+klik)
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/exceptions.dart';
import '../../models/models.dart';
import '../../services/providers.dart';
import '../../shared/month_picker.dart';
import '../../shared/widgets.dart';
import 'shift_assignments_provider.dart' show ymd;
import 'working_hours_overrides_provider.dart';

// ------------------------------ Pomoćne funkcije ------------------------------

/// "HH:mm:ss" → "HH:mm".
String _hm(String? hhmmss) {
  if (hhmmss == null) return '';
  final p = hhmmss.split(':');
  return p.length < 2 ? hhmmss : '${p[0]}:${p[1]}';
}

/// `TimeOfDay` → "HH:mm:ss".
String _apiTime(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

int _mins(TimeOfDay t) => t.hour * 60 + t.minute;

// ================================== TAB ==================================

/// Tab „Kalendar" u ekranu Radno vrijeme (ADMIN): mjesečni kalendar gdje se
/// pojedinačni dani mogu označiti kao neradni ili dobiti posebne sate — čime se
/// dobija „jedna sedmica jedni sati, druga drugi". Izuzeci imaju prednost nad
/// sedmičnim šablonom. Radi tek kad backend `/api/working-hours/overrides` bude
/// spreman; do tad se kalendar prikazuje sa sedmičnim default-om (bez čuvanja).
class WorkingHoursCalendarTab extends ConsumerWidget {
  const WorkingHoursCalendarTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasError = ref.watch(
        workingHoursCalendarProvider.select((s) => s.error));

    return Column(
      children: [
        const _MonthBar(),
        if (hasError != null) const _BackendNotice(),
        const _Legend(),
        const Expanded(child: _MonthCalendar()),
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
    final month =
        ref.watch(workingHoursCalendarProvider.select((s) => s.month));
    final ctrl = ref.read(workingHoursCalendarProvider.notifier);

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

/// Kratka legenda (šta koja boja znači).
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget dot(Color c, String t) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 10,
                height: 10,
                decoration:
                    BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 4),
            Text(t, style: Theme.of(context).textTheme.labelSmall),
          ],
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Wrap(
        spacing: 14,
        runSpacing: 4,
        children: [
          dot(cs.primary, 'Poseban dan (izuzetak)'),
          dot(cs.error, 'Neradni dan'),
          dot(cs.outlineVariant, 'Sedmični raspored'),
        ],
      ),
    );
  }
}

/// Blaga poruka kad backend za izuzetke još nije spreman (ne ruši ekran).
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
              'Izuzeci se ne mogu učitati/sačuvati — backend za radno vrijeme po '
              'datumu još nije spreman.',
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

/// Veliki mjesečni kalendar (7 kolona × sedmice), ćelije se čekiraju.
class _MonthCalendar extends ConsumerWidget {
  const _MonthCalendar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workingHoursCalendarProvider);
    final ctrl = ref.read(workingHoursCalendarProvider.notifier);
    final month = state.month;

    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = DateTime(month.year, month.month, 1).weekday - 1; // Pon=1
    final weeks = ((leading + daysInMonth) / 7).ceil();

    final cells = <DateTime?>[
      for (var i = 0; i < weeks * 7; i++)
        (i - leading + 1) >= 1 && (i - leading + 1) <= daysInMonth
            ? DateTime(month.year, month.month, i - leading + 1)
            : null,
    ];

    void onTapDay(DateTime date) {
      final day = ymd(date);
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
                            child: Builder(builder: (_) {
                              final date = cells[w * 7 + i];
                              if (date == null) {
                                return const _EmptyCell();
                              }
                              final day = ymd(date);
                              return _DayCell(
                                date: date,
                                dayOverride: state.overrideForDay(day),
                                weekly: state.weeklyForDate(date),
                                selected: state.selectedDays.contains(day),
                                onTap: () => onTapDay(date),
                              );
                            }),
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

class _EmptyCell extends StatelessWidget {
  const _EmptyCell();
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}

/// Jedna ćelija: broj dana + status (izuzetak jak, sedmični default blijed).
class _DayCell extends StatelessWidget {
  final DateTime date;
  final WorkingHoursOverrideResponse? dayOverride;
  final WorkingHoursResponse? weekly;
  final bool selected;
  final VoidCallback onTap;

  const _DayCell({
    required this.date,
    required this.dayOverride,
    required this.weekly,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Odredi tekst + boju: izuzetak (jak) ima prednost nad sedmičnim (blijed).
    String label;
    Color labelColor;
    Color? fill;
    if (dayOverride != null) {
      if (dayOverride!.closed) {
        label = 'Zatvoreno';
        labelColor = cs.error;
        fill = cs.errorContainer.withValues(alpha: 0.45);
      } else {
        label = '${_hm(dayOverride!.opensAt)}–${_hm(dayOverride!.closesAt)}';
        labelColor = cs.onPrimaryContainer;
        fill = cs.primaryContainer.withValues(alpha: 0.55);
      }
    } else if (weekly != null) {
      label = '${_hm(weekly!.opensAt)}–${_hm(weekly!.closesAt)}';
      labelColor = cs.onSurfaceVariant;
      fill = null;
    } else {
      label = 'Zatvoreno';
      labelColor = cs.onSurfaceVariant.withValues(alpha: 0.6);
      fill = null;
    }

    final bg = selected ? cs.primary.withValues(alpha: 0.18) : (fill ?? cs.surface);
    final borderColor = selected ? cs.primary : cs.outlineVariant;

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
              border:
                  Border.all(color: borderColor, width: selected ? 2 : 1),
            ),
            padding: const EdgeInsets.all(4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('${date.day}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12)),
                    const Spacer(),
                    if (selected)
                      Icon(Icons.check_circle, size: 14, color: cs.primary),
                  ],
                ),
                const Spacer(),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: labelColor,
                    fontWeight:
                        dayOverride != null ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Donja traka: broj izabranih dana + akcije (postavi vrijeme / neradno / vrati).
class _ActionBar extends ConsumerWidget {
  const _ActionBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(
        workingHoursCalendarProvider.select((s) => s.selectedDays.length));
    final theme = Theme.of(context);
    final isAdmin = ref.watch(authControllerProvider).isAdmin;

    // Zaposleni (ne-admin) vidi kalendar samo za pregled — bez akcija.
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

    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: count == 0
              ? Text('Čekiraj dane u kalendaru (Ctrl+klik = opseg).',
                  style: theme.textTheme.bodyMedium)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Izabrano dana: $count',
                        style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _revert(context, ref),
                          icon: const Icon(Icons.undo, size: 18),
                          label: const Text('Vrati na sedmično'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _markClosed(context, ref),
                          icon: const Icon(Icons.block, size: 18),
                          label: const Text('Neradni dan'),
                        ),
                        FilledButton.icon(
                          onPressed: () => _setHours(context, ref),
                          icon: const Icon(Icons.schedule, size: 18),
                          label: const Text('Postavi vrijeme'),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _setHours(BuildContext context, WidgetRef ref) async {
    final ctrl = ref.read(workingHoursCalendarProvider.notifier);
    final days = ref.read(workingHoursCalendarProvider).selectedDays;
    final res = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const _HoursDialog(),
    );
    if (res == null) return;
    try {
      await ctrl.setHours(days, res.$1, res.$2);
      if (context.mounted) {
        showSnack(context, 'Radno vrijeme postavljeno (${days.length} dana).');
      }
    } catch (e) {
      if (context.mounted) {
        showSnack(context, ApiException.from(e).message, isError: true);
      }
    }
  }

  Future<void> _markClosed(BuildContext context, WidgetRef ref) async {
    final ctrl = ref.read(workingHoursCalendarProvider.notifier);
    final days = ref.read(workingHoursCalendarProvider).selectedDays;
    try {
      await ctrl.markClosed(days);
      if (context.mounted) {
        showSnack(context, 'Označeno kao neradno (${days.length} dana).');
      }
    } catch (e) {
      if (context.mounted) {
        showSnack(context, ApiException.from(e).message, isError: true);
      }
    }
  }

  Future<void> _revert(BuildContext context, WidgetRef ref) async {
    final ctrl = ref.read(workingHoursCalendarProvider.notifier);
    final days = ref.read(workingHoursCalendarProvider).selectedDays;
    final ok = await confirmDialog(
      context,
      title: 'Vrati na sedmično',
      message:
          'Ukloniti posebne postavke za izabrane dane (vraćaju se na sedmični raspored)?',
      confirmText: 'Vrati',
    );
    if (!ok) return;
    try {
      await ctrl.revert(days);
      if (context.mounted) showSnack(context, 'Vraćeno na sedmični raspored.');
    } catch (e) {
      if (context.mounted) {
        showSnack(context, ApiException.from(e).message, isError: true);
      }
    }
  }
}

/// Dijalog: unos radnog vremena (otvaranje/zatvaranje) za izabrane dane.
class _HoursDialog extends StatefulWidget {
  const _HoursDialog();

  @override
  State<_HoursDialog> createState() => _HoursDialogState();
}

class _HoursDialogState extends State<_HoursDialog> {
  TimeOfDay _open = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _close = const TimeOfDay(hour: 21, minute: 0);

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
    if (_mins(_close) <= _mins(_open)) {
      showSnack(context, 'Zatvaranje mora biti poslije otvaranja.',
          isError: true);
      return;
    }
    Navigator.of(context).pop((_apiTime(_open), _apiTime(_close)));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Radno vrijeme za izabrane dane'),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
              child: _timeField(
                  'Otvara', _open, (t) => setState(() => _open = t))),
          const SizedBox(width: 8),
          Expanded(
              child: _timeField(
                  'Zatvara', _close, (t) => setState(() => _close = t))),
        ],
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
