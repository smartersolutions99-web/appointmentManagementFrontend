import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../router/app_router.dart';
import '../../services/providers.dart';
import '../../shared/format.dart';
import '../../shared/widgets.dart';
import '../reports/reports_provider.dart';
import 'barber_stats_provider.dart';

/// Jedna prečica (kartica) na početnoj strani.
class _ShortcutData {
  final IconData icon;
  final String label;
  final String route;

  const _ShortcutData(this.icon, this.label, this.route);
}

/// Početni ekran. Pozdravlja korisnika, prikazuje kratku statistiku prihoda
/// (samo admin) i nudi velike kartice-prečice koje POPUNE ostatak ekrana.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final theme = Theme.of(context);

    // Prečice zavise od uloge: admin vidi 4, običan zaposleni 2.
    final shortcuts = <_ShortcutData>[
      const _ShortcutData(Icons.event, 'Termini', Routes.appointments),
      const _ShortcutData(Icons.people, 'Klijenti', Routes.customers),
      if (auth.isAdmin) ...[
        const _ShortcutData(Icons.badge, 'Zaposleni', Routes.employees),
        const _ShortcutData(Icons.bar_chart, 'Izvještaji', Routes.reports),
      ],
    ];

    // Cijela strana je Column koji popunjava ekran (bez skrolovanja).
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ----- Zaglavlje -----
          Text('Dobrodošli 👋', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'Uloga: ${auth.role ?? 'korisnik'}',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
          ),
          const SizedBox(height: 16),

          // ----- Prihod (samo admin) -----
          if (auth.isAdmin) ...[
            const _RevenueCard(),
            const SizedBox(height: 16),
          ],

          // ----- Statistika dana (samo barber / ne-admin) -----
          if (!auth.isAdmin) ...[
            const _BarberStatsCard(),
            const SizedBox(height: 16),
          ],

          Text('Brze prečice', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),

          // ----- Kartice koje popunjavaju ostatak ekrana -----
          // `Expanded` daje mreži svu preostalu visinu, pa nema skrolovanja.
          Expanded(child: _ShortcutsGrid(items: shortcuts)),
        ],
      ),
    );
  }
}

/// Mreža kartica-prečica koja popunjava raspoloživi prostor.
///
/// Broj kolona računamo prema broju kartica, a sve kartice su jednake veličine
/// jer koristimo `Expanded` i u redovima (širina) i u kolonama (visina).
class _ShortcutsGrid extends StatelessWidget {
  final List<_ShortcutData> items;

  const _ShortcutsGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    const spacing = 12.0;

    if (items.isEmpty) return const SizedBox.shrink();

    // Broj kolona prema broju kartica:
    //  1 kartica -> 1 kolona, 2-4 kartice -> 2 kolone, 5+ -> 3 kolone.
    final columns = items.length <= 1 ? 1 : (items.length <= 4 ? 2 : 3);
    // Broj redova = zaokruženo naviše (npr. 4 kartice / 2 kolone = 2 reda).
    final rows = (items.length / columns).ceil();

    return Column(
      children: [
        for (var r = 0; r < rows; r++) ...[
          if (r > 0) const SizedBox(height: spacing),
          // Svaki red dobija jednak dio visine.
          Expanded(
            child: Row(
              children: [
                for (var c = 0; c < columns; c++) ...[
                  if (c > 0) const SizedBox(width: spacing),
                  // Svaka ćelija dobija jednak dio širine.
                  Expanded(
                    child: _buildCell(r * columns + c),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Vraća karticu za dati indeks, ili prazno mjesto (da širine ostanu jednake
  /// kada poslednji red nije popunjen do kraja).
  Widget _buildCell(int index) {
    if (index >= items.length) return const SizedBox.shrink();
    return _ShortcutCard(item: items[index]);
  }
}

/// Velika kartica-prečica sa ikonicom i nazivom (popunjava svoju ćeliju).
class _ShortcutCard extends StatelessWidget {
  final _ShortcutData item;

  const _ShortcutCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: () => context.go(item.route),
        borderRadius: BorderRadius.circular(16),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.icon, size: 44, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text(item.label, style: theme.textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kartica sa prihodom salona (posljednjih 30 dana) — vidi je samo admin.
class _RevenueCard extends ConsumerWidget {
  const _RevenueCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final summaryAsync = ref.watch(last30DaysRevenueProvider);

    return AsyncValueView<RevenueSummary>(
      value: summaryAsync,
      onRetry: () => ref.invalidate(last30DaysRevenueProvider),
      data: (summary) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Prihod (30 dana)', style: theme.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(
                    Format.money(summary.totalRevenue),
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Završenih', style: theme.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text('${summary.completedAppointments}',
                      style: theme.textTheme.headlineSmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kartica sa današnjom statistikom barbera (broj termina, završeni, sljedeći).
class _BarberStatsCard extends ConsumerWidget {
  const _BarberStatsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final statsAsync = ref.watch(barberTodayStatsProvider);

    return AsyncValueView<BarberTodayStats>(
      value: statsAsync,
      onRetry: () => ref.invalidate(barberTodayStatsProvider),
      data: (stats) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Danas', style: theme.textTheme.titleMedium),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _StatItem(label: 'Termina', value: '${stats.total}'),
                  _StatItem(label: 'Završeno', value: '${stats.completed}'),
                  _StatItem(label: 'Preostalo', value: '${stats.upcoming}'),
                ],
              ),
              const SizedBox(height: 12),
              // Sljedeći termin (ako postoji).
              Row(
                children: [
                  Icon(Icons.schedule,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    stats.nextStart != null
                        ? 'Sljedeći termin u ${Format.time(stats.nextStart)}'
                        : 'Nema više zakazanih termina danas',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Jedna stavka statistike (veliki broj + naziv ispod).
class _StatItem extends StatelessWidget {
  final String label;
  final String value;

  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
