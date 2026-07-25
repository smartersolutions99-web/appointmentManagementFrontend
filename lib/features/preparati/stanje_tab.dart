import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/exceptions.dart';
import '../../shared/format.dart';
import '../../shared/widgets.dart';
import 'stanje_provider.dart';

/// Tab „Stanje" (samo ADMIN): za izabrani period prikazuje ukupnu nabavku,
/// ukupnu prodaju, čist plus i pregled po proizvodu (nabavljeno/prodato).
class StanjeTab extends ConsumerWidget {
  const StanjeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(stanjePeriodProvider);
    final async = ref.watch(stanjeProvider);

    return Column(
      children: [
        _PeriodBar(period: period),
        Expanded(
          child: async.when(
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(
              message: ApiException.from(e).message,
              onRetry: () => ref.invalidate(stanjeProvider),
            ),
            data: (s) => _StanjeContent(summary: s),
          ),
        ),
      ],
    );
  }
}

/// Gornja traka: „Ovaj mjesec", „Prošli mjesec" i proizvoljan opseg.
class _PeriodBar extends ConsumerWidget {
  final DateTimeRange period;
  const _PeriodBar({required this.period});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    void setThisMonth() {
      final now = DateTime.now();
      ref.read(stanjePeriodProvider.notifier).state = DateTimeRange(
        start: DateTime(now.year, now.month, 1),
        end: DateTime(now.year, now.month + 1, 0),
      );
    }

    void setLastMonth() {
      final now = DateTime.now();
      ref.read(stanjePeriodProvider.notifier).state = DateTimeRange(
        start: DateTime(now.year, now.month - 1, 1),
        end: DateTime(now.year, now.month, 0),
      );
    }

    Future<void> pickCustom() async {
      // `lastDate` mora biti bar do kraja tekućeg mjeseca, jer podrazumijevani
      // period (ovaj mjesec) ide do zadnjeg dana mjeseca — inače bi početni
      // opseg bio POSLIJE `lastDate` i birač se ne bi ni otvorio.
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        initialDateRange: period,
        firstDate: DateTime(2020),
        lastDate: DateTime(now.year + 1, 12, 31),
      );
      if (picked != null) {
        ref.read(stanjePeriodProvider.notifier).state = picked;
      }
    }

    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Dugmad za brzi izbor + proizvoljan opseg. `Wrap` da se lijepo
            // prelome na uskom ekranu (telefon).
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(onPressed: setThisMonth, child: const Text('Ovaj mjesec')),
                TextButton(onPressed: setLastMonth, child: const Text('Prošli mjesec')),
                OutlinedButton.icon(
                  onPressed: pickCustom,
                  icon: const Icon(Icons.date_range, size: 18),
                  label: const Text('Izaberi period'),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${Format.date(period.start)} – ${Format.date(period.end)}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sadržaj: kartice sa zbirovima + tabela po proizvodu.
class _StanjeContent extends StatelessWidget {
  final StanjeSummary summary;
  const _StanjeContent({required this.summary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final net = summary.net;
    final netPositive = net >= 0;
    final green = Colors.green.shade400;
    final red = theme.colorScheme.error;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        // Tri glavne brojke.
        _statCard(
          context,
          icon: Icons.shopping_cart_outlined,
          label: 'Ukupna nabavka',
          value: Format.money(summary.totalPurchase),
          sub: '${summary.purchaseCount} nabavki',
          color: red,
        ),
        const SizedBox(height: 8),
        _statCard(
          context,
          icon: Icons.point_of_sale,
          label: 'Ukupna prodaja',
          value: Format.money(summary.totalSales),
          sub: '${summary.salesCount} prodaja',
          color: green,
        ),
        const SizedBox(height: 8),
        _statCard(
          context,
          icon: netPositive ? Icons.trending_up : Icons.trending_down,
          label: 'Čist plus (prodaja − nabavka)',
          value: Format.money(net),
          sub: netPositive ? 'Pozitivno stanje' : 'Negativno stanje',
          color: netPositive ? green : red,
          emphasized: true,
        ),

        // Napomena o internom uzimanju (ako ga ima).
        if (summary.internalCount > 0) ...[
          const SizedBox(height: 8),
          Card(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.4),
            child: ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('Interno uzeto (za zaposlene)'),
              subtitle: Text('${summary.internalCount} izdavanja'),
              trailing: Text(
                Format.money(summary.internalValue),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],

        const SizedBox(height: 16),
        Text('Po proizvodu', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (summary.products.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: EmptyView(
              message: 'Nema nabavki ni prodaja u ovom periodu.',
              icon: Icons.inventory_2_outlined,
            ),
          )
        else
          _productTable(context, summary.products),
      ],
    );
  }

  /// Velika kartica sa jednom brojkom (nabavka/prodaja/plus).
  Widget _statCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required String sub,
    required Color color,
    bool emphasized = false,
  }) {
    final theme = Theme.of(context);
    return Card(
      elevation: emphasized ? 2 : 0,
      color: emphasized ? color.withValues(alpha: 0.12) : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.18),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.bodyMedium),
                  Text(sub,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.hintColor)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Tabela: Proizvod | Nabavljeno (kom/€) | Prodato (kom/€).
  /// Horizontalno skrolabilna da na telefonu ništa ne „iscuri".
  Widget _productTable(BuildContext context, List<ProductStanje> products) {
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 22,
          columns: const [
            DataColumn(label: Text('Proizvod')),
            DataColumn(label: Text('Nabavljeno'), numeric: true),
            DataColumn(label: Text('Nabavka €'), numeric: true),
            DataColumn(label: Text('Prodato'), numeric: true),
            DataColumn(label: Text('Prodaja €'), numeric: true),
          ],
          rows: [
            for (final p in products)
              DataRow(cells: [
                DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Text(p.name, overflow: TextOverflow.ellipsis),
                  ),
                ),
                DataCell(Text('${p.purchasedQty}')),
                DataCell(Text(Format.money(p.purchasedValue))),
                DataCell(Text('${p.soldQty}')),
                DataCell(Text(Format.money(p.soldValue))),
              ]),
          ],
        ),
      ),
    );
  }
}
