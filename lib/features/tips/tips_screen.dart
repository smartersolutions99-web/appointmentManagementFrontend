import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/exceptions.dart';
import '../../models/models.dart';
import '../../services/providers.dart';
import '../../shared/format.dart';
import '../../shared/widgets.dart';
import '../employees/employees_provider.dart';
import 'tips_provider.dart';

/// Ekran „Bakšiš" — unos dnevnog ukupnog bakšiša + pregled po periodu.
/// ADMIN vidi/unosi za sve zaposlene; EMPLOYEE samo za sebe (backend provjerava
/// i pregledi mu automatski vraćaju samo njegovo).
class TipsScreen extends ConsumerWidget {
  const TipsScreen({super.key});

  Future<void> _addDaily(BuildContext context, WidgetRef ref) async {
    final request = await showDialog<TipDailyRequest>(
      context: context,
      builder: (_) => const _DailyTipDialog(),
    );
    if (request == null) return;
    try {
      await ref.read(apiServiceProvider).putDailyTip(request);
      refreshTips(ref);
      if (context.mounted) showSnack(context, 'Bakšiš sačuvan.');
    } catch (e) {
      if (context.mounted) {
        showSnack(context, ApiException.from(e).message, isError: true);
      }
    }
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, TipResponse tip) async {
    final ok = await confirmDialog(
      context,
      title: 'Obriši bakšiš',
      message: 'Obrisati ovaj unos bakšiša?',
      confirmText: 'Obriši',
    );
    if (!ok || tip.id == null) return;
    try {
      await ref.read(apiServiceProvider).deleteTip(tip.id!);
      refreshTips(ref);
      if (context.mounted) showSnack(context, 'Obrisano.');
    } catch (e) {
      if (context.mounted) {
        showSnack(context, ApiException.from(e).message, isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(tipsRangeProvider);
    final totalAsync = ref.watch(tipsTotalProvider);
    final summaryAsync = ref.watch(tipsSummaryProvider);
    final listAsync = ref.watch(tipsListProvider);
    final theme = Theme.of(context);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addDaily(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Dodaj bakšiš'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
        children: [
          const _TipPeriods(),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.date_range),
              title: const Text('Period'),
              subtitle:
                  Text('${Format.date(range.start)} — ${Format.date(range.end)}'),
              trailing: TextButton(
                onPressed: () async {
                  final picked = await showDateRangePicker(
                    context: context,
                    initialDateRange: range,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                  );
                  if (picked != null) {
                    ref.read(tipsRangeProvider.notifier).state = picked;
                  }
                },
                child: const Text('Promijeni'),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Ukupan bakšiš za period.
          AsyncValueView<TipTotal>(
            value: totalAsync,
            onRetry: () => ref.invalidate(tipsTotalProvider),
            data: (t) => Card(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ukupan bakšiš', style: theme.textTheme.bodySmall),
                    const SizedBox(height: 4),
                    Text(Format.money(t.total),
                        style: theme.textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Po zaposlenom.
          Text('Po zaposlenom', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          AsyncValueView<List<TipSummary>>(
            value: summaryAsync,
            onRetry: () => ref.invalidate(tipsSummaryProvider),
            data: (rows) {
              if (rows.isEmpty) {
                return const EmptyView(
                    message: 'Nema bakšiša u ovom periodu.',
                    icon: Icons.volunteer_activism_outlined);
              }
              final sorted = [...rows]
                ..sort((a, b) => b.totalTips.compareTo(a.totalTips));
              return Card(
                child: Column(
                  children: [
                    for (final s in sorted)
                      ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          child: Text((s.employeeName?.isNotEmpty ?? false)
                              ? s.employeeName![0].toUpperCase()
                              : '?'),
                        ),
                        title: Text(s.employeeName ?? 'Zaposleni ${s.employeeId}'),
                        trailing: Text(Format.money(s.totalTips),
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 24),

          // Pojedinačni unosi (sa brisanjem).
          Text('Unosi', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          AsyncValueView<List<TipResponse>>(
            value: listAsync,
            onRetry: () => ref.invalidate(tipsListProvider),
            data: (tips) {
              if (tips.isEmpty) {
                return const EmptyView(message: 'Nema unosa bakšiša.');
              }
              final sorted = [...tips]
                ..sort((a, b) => (b.date ?? '').compareTo(a.date ?? ''));
              return Column(
                children: [
                  for (final tip in sorted)
                    Card(
                      child: ListTile(
                        leading: Icon(tip.appointmentId != null
                            ? Icons.event_available
                            : Icons.savings_outlined),
                        title: Text(Format.money(tip.amount ?? 0),
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text([
                          if (tip.employeeName != null) tip.employeeName!,
                          if (tip.date != null) tip.date!,
                          if (tip.appointmentId != null)
                            'termin #${tip.appointmentId}',
                          if (tip.note != null && tip.note!.isNotEmpty)
                            tip.note!,
                        ].join(' • ')),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Obriši',
                          onPressed: () => _delete(context, ref, tip),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Brzi izbor perioda za bakšiš.
class _TipPeriods extends ConsumerWidget {
  const _TipPeriods();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void set(DateTimeRange r) =>
        ref.read(tipsRangeProvider.notifier).state = r;
    final now = DateTime.now();

    return Wrap(
      spacing: 8,
      children: [
        ActionChip(
          label: const Text('Ovaj mjesec'),
          onPressed: () =>
              set(DateTimeRange(start: DateTime(now.year, now.month), end: now)),
        ),
        ActionChip(
          label: const Text('Prošli mjesec'),
          onPressed: () {
            final firstThis = DateTime(now.year, now.month);
            final firstPrev = DateTime(now.year, now.month - 1);
            set(DateTimeRange(
                start: firstPrev,
                end: firstThis.subtract(const Duration(days: 1))));
          },
        ),
        ActionChip(
          label: const Text('Posljednjih 30 dana'),
          onPressed: () =>
              set(DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now)),
        ),
      ],
    );
  }
}

/// Dijalog za unos DNEVNOG ukupnog bakšiša. Admin bira zaposlenog; zaposleni je
/// zaključan na sebe. Vraća [TipDailyRequest] ili `null` (otkaz).
class _DailyTipDialog extends ConsumerStatefulWidget {
  const _DailyTipDialog();

  @override
  ConsumerState<_DailyTipDialog> createState() => _DailyTipDialogState();
}

class _DailyTipDialogState extends ConsumerState<_DailyTipDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  DateTime _date = DateTime.now();
  int? _employeeId;
  late final bool _isAdmin;

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authControllerProvider);
    _isAdmin = auth.isAdmin;
    if (!_isAdmin) _employeeId = auth.employeeId; // zaposleni → sebi
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_employeeId == null) {
      showSnack(context, 'Izaberite zaposlenog.', isError: true);
      return;
    }
    Navigator.pop(
      context,
      TipDailyRequest(
        employeeId: _employeeId!,
        date: tipYmd(_date),
        amount: double.parse(_amount.text.replaceAll(',', '.')),
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Dnevni bakšiš'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Izbor zaposlenog — samo admin.
              if (_isAdmin) ...[
                ref.watch(employeesProvider).when(
                      loading: () => const LinearProgressIndicator(),
                      error: (e, _) => Text(ApiException.from(e).message,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                      data: (emps) => DropdownButtonFormField<int>(
                        value: _employeeId,
                        isExpanded: true,
                        decoration:
                            const InputDecoration(labelText: 'Zaposleni'),
                        items: [
                          for (final e in emps)
                            DropdownMenuItem(
                                value: e.id,
                                child: Text(e.name ?? 'Zaposleni ${e.id}')),
                        ],
                        onChanged: (v) => setState(() => _employeeId = v),
                      ),
                    ),
                const SizedBox(height: 12),
              ],
              // Datum.
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today),
                title: const Text('Datum'),
                subtitle: Text(Format.date(_date)),
                trailing: TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                    );
                    if (picked != null) setState(() => _date = picked);
                  },
                  child: const Text('Izmijeni'),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _amount,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Iznos (€)', prefixIcon: Icon(Icons.euro)),
                validator: (v) {
                  final n = double.tryParse((v ?? '').replaceAll(',', '.'));
                  if (n == null || n < 0) return 'Unesite ispravan iznos';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _note,
                decoration:
                    const InputDecoration(labelText: 'Napomena (opciono)'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Otkaži'),
        ),
        FilledButton(onPressed: _save, child: const Text('Sačuvaj')),
      ],
    );
  }
}
