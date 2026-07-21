import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/exceptions.dart';
import '../../models/models.dart';
import '../../shared/widgets.dart';
import 'shift_templates_provider.dart';

// ------------------------- Pomoćne funkcije za vrijeme -------------------------

/// "HH:mm" iz `TimeOfDay` (za prikaz na dugmadima).
String _fmt(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// "HH:mm:ss" iz `TimeOfDay` (format koji očekuje server).
String _toApi(TimeOfDay t) => '${_fmt(t)}:00';

/// `TimeOfDay` iz servera "HH:mm:ss" (ili zadata rezerva ako je prazno/neispravno).
TimeOfDay _parse(String? hhmmss, TimeOfDay fallback) {
  if (hhmmss == null) return fallback;
  final parts = hhmmss.split(':');
  if (parts.length < 2) return fallback;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return fallback;
  return TimeOfDay(hour: h, minute: m);
}

/// Broj minuta od ponoći — zgodno za poređenje (kraj mora biti poslije početka).
int _minutes(TimeOfDay t) => t.hour * 60 + t.minute;

/// Izmjenjivo stanje jednog dana u formi.
class _DayEdit {
  bool enabled; // da li se radi tog dana
  TimeOfDay start;
  TimeOfDay end;

  _DayEdit({required this.enabled, required this.start, required this.end});
}

/// Forma (cijeli ekran) za kreiranje/izmjenu šablona smjene.
///
/// Šablon = naziv + (opciono) napomena + spisak radnih dana sa vremenima.
/// Dani koji nisu označeni su „slobodni“ u ovom šablonu. Forma sama poziva
/// server (create/update/delete) i po uspjehu se zatvara.
class ShiftTemplateFormScreen extends ConsumerStatefulWidget {
  /// Ako je zadat — uređujemo postojeći šablon; inače pravimo novi.
  final ShiftTemplateResponse? existing;

  const ShiftTemplateFormScreen({super.key, this.existing});

  @override
  ConsumerState<ShiftTemplateFormScreen> createState() =>
      _ShiftTemplateFormScreenState();
}

class _ShiftTemplateFormScreenState
    extends ConsumerState<ShiftTemplateFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _note;

  // Podrazumijevana radna vremena za novooznačen dan.
  static const _defaultStart = TimeOfDay(hour: 9, minute: 0);
  static const _defaultEnd = TimeOfDay(hour: 17, minute: 0);

  // „Brzi unos“: vrijeme koje jednim klikom postavljamo na SVE označene dane
  // (da ne moramo unositi dan po dan).
  TimeOfDay _bulkStart = _defaultStart;
  TimeOfDay _bulkEnd = _defaultEnd;

  // Stanje po danu (uvijek svih 7, u redoslijedu Pon→Ned).
  late final Map<WeekDay, _DayEdit> _days;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _note = TextEditingController(text: existing?.note ?? '');

    // Postojeći dani (ako uređujemo) — mapa po danu za brzo popunjavanje.
    final byDay = <WeekDay, ShiftTemplateDayResponse>{
      for (final d in existing?.days ?? const []) d.dayOfWeek: d,
    };

    _days = {
      for (final day in WeekDay.values)
        day: _DayEdit(
          enabled: byDay.containsKey(day),
          start: _parse(byDay[day]?.startTime, _defaultStart),
          end: _parse(byDay[day]?.endTime, _defaultEnd),
        ),
    };
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Otvori „sat“ i vrati izabrano vrijeme (24h format).
  Future<TimeOfDay?> _pickTime(TimeOfDay initial) {
    return showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) => MediaQuery(
        // Salon koristi 24-časovni prikaz vremena.
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
  }

  /// Primijeni „brzi unos“ (Od/Do) na sve trenutno označene dane.
  void _applyBulk() {
    final enabled = _days.values.where((d) => d.enabled).toList();
    if (enabled.isEmpty) {
      showSnack(context, 'Prvo označite dane na koje želite vrijeme.',
          isError: true);
      return;
    }
    if (_minutes(_bulkEnd) <= _minutes(_bulkStart)) {
      showSnack(context, 'Kraj mora biti poslije početka.', isError: true);
      return;
    }
    setState(() {
      for (final d in enabled) {
        d.start = _bulkStart;
        d.end = _bulkEnd;
      }
    });
    showSnack(context, 'Vrijeme postavljeno na ${enabled.length} označenih dana.');
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // Skupi označene (radne) dane u pravilnom poretku.
    final enabled = [
      for (final day in WeekDay.values)
        if (_days[day]!.enabled) day,
    ];

    if (enabled.isEmpty) {
      showSnack(context, 'Izaberite bar jedan radni dan.', isError: true);
      return;
    }

    // Provjeri da je kraj poslije početka za svaki radni dan.
    for (final day in enabled) {
      final d = _days[day]!;
      if (_minutes(d.end) <= _minutes(d.start)) {
        showSnack(
          context,
          'Kraj mora biti poslije početka (${day.label}).',
          isError: true,
        );
        return;
      }
    }

    final request = ShiftTemplateRequest(
      name: _name.text.trim(),
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      days: [
        for (final day in enabled)
          ShiftTemplateDayRequest(
            dayOfWeek: day,
            startTime: _toApi(_days[day]!.start),
            endTime: _toApi(_days[day]!.end),
          ),
      ],
    );

    setState(() => _saving = true);
    try {
      final ctrl = ref.read(shiftTemplatesControllerProvider.notifier);
      final id = widget.existing?.id;
      if (id != null) {
        await ctrl.update(id, request);
      } else {
        await ctrl.create(request);
      }
      if (!mounted) return;
      showSnack(context, 'Šablon sačuvan.');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, ApiException.from(e).message, isError: true);
    }
  }

  Future<void> _delete() async {
    final id = widget.existing?.id;
    if (id == null) return;

    final ok = await confirmDialog(
      context,
      title: 'Obriši šablon',
      message: 'Da li sigurno želite da obrišete ovaj šablon smjene?',
      confirmText: 'Obriši',
    );
    if (!ok) return;

    setState(() => _saving = true);
    try {
      await ref.read(shiftTemplatesControllerProvider.notifier).delete(id);
      if (!mounted) return;
      showSnack(context, 'Šablon obrisan.');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      // Npr. 409 RESOURCE_IN_USE ako je šablon dodijeljen nekom zaposlenom.
      showSnack(context, ApiException.from(e).message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Izmjena šablona' : 'Novi šablon smjene'),
        actions: [
          if (isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Obriši',
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Naziv šablona',
                hintText: 'npr. Marko — standardna nedjelja',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Obavezno polje' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _note,
              decoration: const InputDecoration(
                labelText: 'Napomena (opciono)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 20),
            Text('Radni dani', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Označite dane kada se radi i unesite vrijeme. Neoznačeni dani su slobodni.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            _buildBulkCard(),
            const SizedBox(height: 8),
            for (final day in WeekDay.values) _buildDayRow(day),
            const SizedBox(height: 20),
            // Puna širina je ovdje bezbjedna (dugme je u tijelu sa ograničenom
            // širinom, a ne u bottomNavigationBar-u).
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
        ),
      ),
    );
  }

  /// „Brzi unos“: postavi isto vrijeme za sve označene dane jednim klikom.
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
                _timeButton(
                    'Od', _bulkStart, (t) => setState(() => _bulkStart = t)),
                const SizedBox(width: 8),
                _timeButton(
                    'Do', _bulkEnd, (t) => setState(() => _bulkEnd = t)),
              ],
            ),
            const SizedBox(height: 8),
            // Puna širina (u tijelu je, ograničena širina — bezbjedno).
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

  /// Jedan red: prekidač (radi/ne radi) + naziv dana + vremena (od/do).
  Widget _buildDayRow(WeekDay day) {
    final d = _days[day]!;
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            // Checkbox + naziv dana (fiksna širina da su vremena poravnata).
            SizedBox(
              width: 150,
              child: Row(
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
              ),
            ),
            // Vremena (ako radi) ili oznaka „Slobodan dan“.
            Expanded(
              child: d.enabled
                  ? Row(
                      children: [
                        _timeButton('Od', d.start,
                            (t) => setState(() => d.start = t)),
                        const SizedBox(width: 8),
                        _timeButton(
                            'Do', d.end, (t) => setState(() => d.end = t)),
                      ],
                    )
                  : Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        'Slobodan dan',
                        style: TextStyle(color: theme.hintColor),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Dugme koje otvara „sat“ i prikazuje izabrano vrijeme (npr. "Od: 09:00").
  Widget _timeButton(
      String label, TimeOfDay value, ValueChanged<TimeOfDay> onPicked) {
    return Expanded(
      child: OutlinedButton.icon(
        icon: const Icon(Icons.schedule, size: 18),
        onPressed: () async {
          final picked = await _pickTime(value);
          if (picked != null) onPicked(picked);
        },
        label: Text('$label: ${_fmt(value)}'),
      ),
    );
  }
}

/// Otvara formu (cijeli ekran). Forma sama čuva/briše i po uspjehu se zatvara.
Future<void> showShiftTemplateForm(
  BuildContext context, {
  ShiftTemplateResponse? existing,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ShiftTemplateFormScreen(existing: existing),
    ),
  );
}
