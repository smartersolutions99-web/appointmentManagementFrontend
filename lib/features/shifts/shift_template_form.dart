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

  /// Kad je `true`, forma je „samo pregled" (za zaposlene): polja su zaključana,
  /// bez dugmadi za čuvanje/brisanje.
  final bool readOnly;

  const ShiftTemplateFormScreen({
    super.key,
    this.existing,
    this.readOnly = false,
  });

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
      initialEntryMode: TimePickerEntryMode.input, // po difoltu unos brojki
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
    final readOnly = widget.readOnly;

    return Scaffold(
      appBar: AppBar(
        title: Text(readOnly
            ? 'Pregled šablona'
            : (isEdit ? 'Izmjena šablona' : 'Novi šablon smjene')),
        actions: [
          if (isEdit && !readOnly)
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
            if (readOnly) ...[
              const ReadOnlyBanner(),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _name,
              readOnly: readOnly,
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
              readOnly: readOnly,
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
              readOnly
                  ? 'Dani i vremena ovog šablona (neoznačeni dani su slobodni).'
                  : 'Označite dane kada se radi i unesite vrijeme. Neoznačeni dani su slobodni.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (!readOnly) ...[
              _buildBulkCard(),
              const SizedBox(height: 8),
            ],
            for (final day in WeekDay.values) _buildDayRow(day),
            const SizedBox(height: 20),
            // Dugme „Sačuvaj" postoji samo kad nije „samo pregled".
            if (!readOnly)
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
  /// Responzivno: na uskom (telefon) vremena idu ISPOD dana (pa dobijaju punu
  /// širinu), na širem ekranu dan je lijevo a vremena desno.
  Widget _buildDayRow(WeekDay day) {
    final d = _days[day]!;
    final theme = Theme.of(context);

    final header = Row(
      children: [
        Checkbox(
          value: d.enabled,
          onChanged: widget.readOnly
              ? null
              : (v) => setState(() => d.enabled = v ?? false),
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
        _timeButton('Od', d.start, (t) => setState(() => d.start = t)),
        const SizedBox(width: 8),
        _timeButton('Do', d.end, (t) => setState(() => d.end = t)),
      ],
    );

    final free = Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text('Slobodan dan', style: TextStyle(color: theme.hintColor)),
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
                    Align(alignment: Alignment.centerLeft, child: free),
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
                      : Align(alignment: Alignment.centerLeft, child: free),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Polje vremena: mala labela ("Od") iznad, pa dugme koje pokazuje SAMO
  /// vrijeme (npr. "09:00") i otvara „sat". Time se tekst nikad ne lomi.
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
            onPressed: widget.readOnly
                ? null
                : () async {
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

/// Otvara formu (cijeli ekran). Forma sama čuva/briše i po uspjehu se zatvara.
/// Kad je `readOnly` true, otvara se u režimu „samo pregled" (za zaposlene).
Future<void> showShiftTemplateForm(
  BuildContext context, {
  ShiftTemplateResponse? existing,
  bool readOnly = false,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) =>
          ShiftTemplateFormScreen(existing: existing, readOnly: readOnly),
    ),
  );
}
