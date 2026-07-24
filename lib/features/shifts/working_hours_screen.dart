import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/exceptions.dart';
import '../../models/models.dart';
import '../../services/providers.dart';
import '../../shared/widgets.dart';

// ------------------------- Pomoćne funkcije za vrijeme -------------------------

/// "HH:mm" iz `TimeOfDay` (za prikaz).
String _fmt(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// "HH:mm:ss" iz `TimeOfDay` (format koji očekuje server).
String _toApi(TimeOfDay t) => '${_fmt(t)}:00';

/// `TimeOfDay` iz servera "HH:mm:ss" (ili zadata rezerva ako fali/neispravno).
TimeOfDay _parse(String? hhmmss, TimeOfDay fallback) {
  if (hhmmss == null) return fallback;
  final parts = hhmmss.split(':');
  if (parts.length < 2) return fallback;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return fallback;
  return TimeOfDay(hour: h, minute: m);
}

/// Minuti od ponoći — za poređenje (zatvaranje mora biti poslije otvaranja).
int _minutes(TimeOfDay t) => t.hour * 60 + t.minute;

/// Izmjenjivo stanje jednog dana.
class _DayEdit {
  bool enabled; // da li je salon otvoren tog dana
  TimeOfDay opens;
  TimeOfDay closes;

  _DayEdit({required this.enabled, required this.opens, required this.closes});
}

/// Ekran „Radno vrijeme“ (ADMIN): radno vrijeme salona po danima u sedmici.
///
/// Učita trenutno stanje, dozvoli izmjenu (dan po dan ili „brzi unos“ za sve
/// označene dane) i sačuva ga jednim pozivom (zamjena cijele sedmice).
class WorkingHoursScreen extends ConsumerStatefulWidget {
  const WorkingHoursScreen({super.key});

  @override
  ConsumerState<WorkingHoursScreen> createState() => _WorkingHoursScreenState();
}

class _WorkingHoursScreenState extends ConsumerState<WorkingHoursScreen> {
  // Podrazumijevano radno vrijeme za novooznačen dan.
  static const _defOpen = TimeOfDay(hour: 8, minute: 0);
  static const _defClose = TimeOfDay(hour: 21, minute: 0);

  Map<WeekDay, _DayEdit>? _days; // null dok se ne učita
  bool _loading = true;
  bool _saving = false;
  String? _error;

  // „Brzi unos“ — vrijeme koje jednim klikom postavljamo na sve označene dane.
  TimeOfDay _bulkOpen = _defOpen;
  TimeOfDay _bulkClose = _defClose;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ref.read(apiServiceProvider).getWorkingHours();
      _seed(list);
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ApiException.from(e).message;
      });
    }
  }

  /// Napuni lokalno stanje (svih 7 dana) iz odgovora servera.
  void _seed(List<WorkingHoursResponse> list) {
    final byDay = <WeekDay, WorkingHoursResponse>{
      for (final w in list) w.dayOfWeek: w,
    };
    _days = {
      for (final day in WeekDay.values)
        day: _DayEdit(
          enabled: byDay.containsKey(day),
          opens: _parse(byDay[day]?.opensAt, _defOpen),
          closes: _parse(byDay[day]?.closesAt, _defClose),
        ),
    };
  }

  Future<TimeOfDay?> _pickTime(TimeOfDay initial) {
    return showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
  }

  /// Primijeni „brzi unos“ na sve trenutno označene (radne) dane.
  void _applyBulk() {
    final enabled = _days!.values.where((d) => d.enabled).toList();
    if (enabled.isEmpty) {
      showSnack(context, 'Prvo označite radne dane.', isError: true);
      return;
    }
    if (_minutes(_bulkClose) <= _minutes(_bulkOpen)) {
      showSnack(context, 'Zatvaranje mora biti poslije otvaranja.',
          isError: true);
      return;
    }
    setState(() {
      for (final d in enabled) {
        d.opens = _bulkOpen;
        d.closes = _bulkClose;
      }
    });
    showSnack(context, 'Vrijeme postavljeno na ${enabled.length} dana.');
  }

  Future<void> _save() async {
    final days = _days!;
    final enabled = [
      for (final day in WeekDay.values)
        if (days[day]!.enabled) day,
    ];

    // Provjeri da je zatvaranje poslije otvaranja za svaki radni dan.
    for (final day in enabled) {
      final d = days[day]!;
      if (_minutes(d.closes) <= _minutes(d.opens)) {
        showSnack(
          context,
          'Zatvaranje mora biti poslije otvaranja (${day.label}).',
          isError: true,
        );
        return;
      }
    }

    // Nijedan dan nije radni → salon zatvoren cijele sedmice: traži potvrdu.
    if (enabled.isEmpty) {
      final ok = await confirmDialog(
        context,
        title: 'Salon zatvoren?',
        message:
            'Nijedan dan nije označen kao radni — salon će biti zatvoren cijele sedmice. Nastaviti?',
        confirmText: 'Sačuvaj',
      );
      if (!ok) return;
    }

    final request = [
      for (final day in enabled)
        WorkingHoursRequest(
          dayOfWeek: day,
          opensAt: _toApi(days[day]!.opens),
          closesAt: _toApi(days[day]!.closes),
        ),
    ];

    setState(() => _saving = true);
    try {
      final updated =
          await ref.read(apiServiceProvider).replaceWorkingHours(request);
      _seed(updated); // osvježi iz servera (izvor istine)
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, 'Radno vrijeme sačuvano.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, ApiException.from(e).message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_days == null) {
      body = _loading
          ? const LoadingView()
          : ErrorView(message: _error ?? 'Greška', onRetry: _load);
    } else {
      body = _buildForm(_days!);
    }
    return Scaffold(body: body);
  }

  Widget _buildForm(Map<WeekDay, _DayEdit> days) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        Text('Radno vrijeme salona',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Označite dane kada je salon otvoren i unesite vrijeme. Neoznačeni dani = zatvoreno.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        _buildBulkCard(),
        const SizedBox(height: 8),
        for (final day in WeekDay.values) _buildDayRow(day, days[day]!),
        const SizedBox(height: 20),
        // Puna širina je bezbjedna (u tijelu je, ograničena širina).
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check),
          label: const Text('Sačuvaj'),
        ),
      ],
    );
  }

  /// „Brzi unos“: isto vrijeme za sve označene dane jednim klikom.
  Widget _buildBulkCard() {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Brzi unos', style: theme.textTheme.titleSmall),
            const SizedBox(height: 2),
            Text(
              'Postavi isto vrijeme za sve trenutno označene dane.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _timeButton('Otvara', _bulkOpen,
                    (t) => setState(() => _bulkOpen = t)),
                const SizedBox(width: 8),
                _timeButton('Zatvara', _bulkClose,
                    (t) => setState(() => _bulkClose = t)),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: _applyBulk,
              icon: const Icon(Icons.done_all),
              label: const Text('Primijeni na označene dane'),
            ),
          ],
        ),
      ),
    );
  }

  /// Jedan red: prekidač (otvoreno/zatvoreno) + naziv dana + vremena.
  /// Responzivno: na uskom (telefon) vremena idu ISPOD dana (pa dobijaju punu
  /// širinu), na širem ekranu dan je lijevo a vremena desno.
  Widget _buildDayRow(WeekDay day, _DayEdit d) {
    final theme = Theme.of(context);

    final header = Row(
      children: [
        Checkbox(
          value: d.enabled,
          onChanged: (v) => setState(() => d.enabled = v ?? false),
        ),
        Expanded(
          child: Text(
            day.label,
            style: const TextStyle(fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    final times = Row(
      children: [
        _timeButton('Otvara', d.opens, (t) => setState(() => d.opens = t)),
        const SizedBox(width: 8),
        _timeButton('Zatvara', d.closes, (t) => setState(() => d.closes = t)),
      ],
    );

    final closed = Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text('Zatvoreno', style: TextStyle(color: theme.hintColor)),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: LayoutBuilder(
          builder: (context, c) {
            if (c.maxWidth < 480) {
              // Usko: dan gore, vremena ispod (puna širina — dovoljno mjesta).
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  if (d.enabled) ...[
                    const SizedBox(height: 6),
                    times,
                  ] else
                    Align(alignment: Alignment.centerLeft, child: closed),
                ],
              );
            }
            // Široko: dan lijevo (fiksna širina), vremena desno.
            return Row(
              children: [
                SizedBox(width: 160, child: header),
                Expanded(
                  child: d.enabled
                      ? times
                      : Align(alignment: Alignment.centerLeft, child: closed),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Polje vremena: mala labela ("Otvara") iznad, pa dugme koje pokazuje SAMO
  /// vrijeme (npr. "08:00") i otvara „sat". Time se tekst nikad ne lomi.
  Widget _timeButton(
      String label, TimeOfDay value, ValueChanged<TimeOfDay> onPicked) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.hintColor)),
          const SizedBox(height: 2),
          OutlinedButton.icon(
            icon: const Icon(Icons.schedule, size: 18),
            style: OutlinedButton.styleFrom(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            onPressed: () async {
              final picked = await _pickTime(value);
              if (picked != null) onPicked(picked);
            },
            label: Text(_fmt(value),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
