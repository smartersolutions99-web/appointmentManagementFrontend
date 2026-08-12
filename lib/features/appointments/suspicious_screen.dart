import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/exceptions.dart';
import '../../models/models.dart';
import '../../services/providers.dart';
import '../../shared/format.dart';
import '../../shared/widgets.dart';
import '../employees/employees_provider.dart';
import 'suspicious_provider.dart';

/// Ekran „Sumnjivi termini" (ADMIN) — termini zakazani znatno NAKON vremena
/// termina (npr. u 15h neko zakaže sebi slot za 11h). Dugme „Razriješi" ih
/// trajno sklanja s liste (status termina se ne dira).
class SuspiciousScreen extends ConsumerWidget {
  const SuspiciousScreen({super.key});

  Future<void> _resolve(
      BuildContext context, WidgetRef ref, AppointmentResponse a) async {
    final ok = await confirmDialog(
      context,
      title: 'Razriješi',
      message:
          'Označiti ovaj termin kao pregledan? Trajno nestaje s liste sumnjivih '
          '(status termina se ne mijenja).',
      confirmText: 'Razriješi',
    );
    if (!ok || a.id == null) return;
    try {
      await ref.read(apiServiceProvider).resolveSuspicious(a.id!);
      ref.invalidate(suspiciousProvider);
      if (context.mounted) showSnack(context, 'Razriješeno.');
    } catch (e) {
      if (context.mounted) {
        showSnack(context, ApiException.from(e).message, isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(suspiciousProvider);
    final gap = ref.watch(suspiciousMinGapProvider);
    final nameById = {
      for (final e in ref.watch(employeesProvider).valueOrNull ?? const [])
        e.id: e.name
    };

    return Scaffold(
      body: Column(
        children: [
          // Prag „sumnjivosti" (koliko sati nakon termina).
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                const Icon(Icons.tune, size: 20),
                const SizedBox(width: 8),
                const Text('Prag: zakazano bar'),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: gap,
                  items: const [
                    DropdownMenuItem(value: 2, child: Text('2 h')),
                    DropdownMenuItem(value: 4, child: Text('4 h')),
                    DropdownMenuItem(value: 6, child: Text('6 h')),
                    DropdownMenuItem(value: 12, child: Text('12 h')),
                    DropdownMenuItem(value: 24, child: Text('24 h')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      ref.read(suspiciousMinGapProvider.notifier).state = v;
                    }
                  },
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('nakon vremena termina',
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: AsyncValueView<List<AppointmentResponse>>(
              value: async,
              onRetry: () => ref.invalidate(suspiciousProvider),
              data: (items) {
                if (items.isEmpty) {
                  return const EmptyView(
                    message: 'Nema sumnjivih termina. 👍',
                    icon: Icons.verified_outlined,
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _SuspiciousCard(
                    appt: items[i],
                    barberName: nameById[items[i].employeeId],
                    onResolve: () => _resolve(context, ref, items[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SuspiciousCard extends StatelessWidget {
  final AppointmentResponse appt;
  final String? barberName;
  final VoidCallback onResolve;

  const _SuspiciousCard({
    required this.appt,
    required this.barberName,
    required this.onResolve,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final start = appt.startTime?.toLocal();
    final booked = appt.createdAt?.toLocal();

    // Koliko sati NAKON termina je zakazan (za oznaku „zašto je sumnjiv").
    String gapLabel = '';
    if (start != null && booked != null) {
      final h = booked.difference(start).inMinutes / 60.0;
      if (h > 0) gapLabel = 'zakazan ${h.toStringAsFixed(1)} h nakon termina';
    }

    final customer = (appt.customerName?.trim().isNotEmpty ?? false)
        ? appt.customerName!.trim()
        : (appt.customerPhone ?? 'Nepoznat klijent');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: theme.colorScheme.error, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(customer,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                if (barberName != null)
                  Chip(
                    label: Text(barberName!),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _row(theme, Icons.event, 'Termin',
                start != null ? Format.dateTime(start) : '—'),
            _row(theme, Icons.schedule, 'Zakazan',
                booked != null ? Format.dateTime(booked) : '—'),
            if (gapLabel.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(gapLabel,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: onResolve,
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Razriješi'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(ThemeData theme, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.hintColor),
          const SizedBox(width: 8),
          SizedBox(
            width: 72,
            child: Text(label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.hintColor)),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
