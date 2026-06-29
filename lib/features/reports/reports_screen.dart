import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../shared/file_download.dart';
import '../../shared/format.dart';
import '../../shared/widgets.dart';
import '../appointments/barber_colors.dart';
import 'reports_provider.dart';

/// Ekran sa izvještajima (samo za administratore).
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  Future<void> _pickRange(BuildContext context, WidgetRef ref) async {
    final current = ref.read(reportRangeProvider);
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: current,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      ref.read(reportRangeProvider.notifier).state = picked;
    }
  }

  /// Sastavi CSV i pokreni preuzimanje/čuvanje (otvara se u Excel-u).
  /// Web: browser preuzima fajl. Desktop: snima ga u folder Downloads.
  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final report = ref.read(detailedReportProvider).value;
    final range = ref.read(reportRangeProvider);
    if (report == null) {
      showSnack(context, 'Sačekajte da se izvještaj učita.', isError: true);
      return;
    }
    try {
      final csv = _buildCsv(report, range);
      final name =
          'izvjestaj_${_fileDate(range.start)}_${_fileDate(range.end)}.csv';
      final path = await downloadTextFile(name, csv);
      if (!context.mounted) return;
      showSnack(
        context,
        path != null ? 'Sačuvano: $path' : 'Izvještaj preuzet: $name',
      );
    } catch (e) {
      if (context.mounted) {
        showSnack(context, 'Greška pri exportu: $e', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(reportRangeProvider);
    final detailedAsync = ref.watch(detailedReportProvider);
    final trendAsync = ref.watch(revenueOverTimeProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ---- Brzi periodi ----
        const _QuickPeriods(),
        const SizedBox(height: 8),

        // ---- Izbor perioda + export ----
        Card(
          child: ListTile(
            leading: const Icon(Icons.date_range),
            title: const Text('Period'),
            subtitle: Text(
              '${Format.date(range.start)} — ${Format.date(range.end)}',
            ),
            trailing: TextButton(
              onPressed: () => _pickRange(context, ref),
              child: const Text('Promijeni'),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonalIcon(
            onPressed: () => _export(context, ref),
            icon: const Icon(Icons.download),
            label: const Text('Izvezi u Excel (CSV)'),
          ),
        ),
        const SizedBox(height: 16),

        // ---- Detaljna statistika ----
        AsyncValueView<DetailedReport>(
          value: detailedAsync,
          onRetry: () => ref.invalidate(detailedReportProvider),
          data: (report) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _OverallCard(report: report),
              const SizedBox(height: 12),
              _KpiCard(report: report),
              const SizedBox(height: 24),

              // Pita grafikon statusa.
              Text('Razrada statusa',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              _StatusPieCard(counts: report.overall),
              const SizedBox(height: 24),

              // Prihod po barberu (grafikon + tabela).
              Text('Statistika po barberu',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (report.barbers.isEmpty)
                const EmptyView(message: 'Nema podataka za ovaj period.')
              else ...[
                _BarberRevenueChart(barbers: report.barbers),
                const SizedBox(height: 12),
                _BarberTable(report: report),
              ],
              const SizedBox(height: 24),

              // Statistika po usluzi.
              Text('Statistika po usluzi',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (report.services.isEmpty)
                const EmptyView(message: 'Nema podataka za ovaj period.')
              else
                _ServiceTable(services: report.services),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ---- Prihod po danu (trend) ----
        Text('Prihod po danu',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        AsyncValueView<List<RevenueBucket>>(
          value: trendAsync,
          onRetry: () => ref.invalidate(revenueOverTimeProvider),
          data: (buckets) {
            if (buckets.isEmpty) {
              return const EmptyView(message: 'Nema podataka za ovaj period.');
            }
            final maxRevenue = buckets
                .map((b) => b.revenue)
                .fold<double>(0, (a, b) => a > b ? a : b);
            return Column(
              children: [
                for (final bucket in buckets)
                  _RevenueBar(bucket: bucket, maxRevenue: maxRevenue),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Dugmad za brzi izbor perioda (Danas / Sedmica / Mjesec / Prošli mjesec).
class _QuickPeriods extends ConsumerWidget {
  const _QuickPeriods();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void set(DateTimeRange r) =>
        ref.read(reportRangeProvider.notifier).state = r;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Wrap(
      spacing: 8,
      children: [
        ActionChip(
          label: const Text('Danas'),
          onPressed: () => set(DateTimeRange(start: today, end: now)),
        ),
        ActionChip(
          label: const Text('Ova sedmica'),
          onPressed: () {
            // Ponedjeljak ove sedmice.
            final monday = today.subtract(Duration(days: today.weekday - 1));
            set(DateTimeRange(start: monday, end: now));
          },
        ),
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
            // Kraj prošlog mjeseca = sekunda prije početka ovog.
            final endPrev = firstThis.subtract(const Duration(seconds: 1));
            set(DateTimeRange(start: firstPrev, end: endPrev));
          },
        ),
      ],
    );
  }
}

/// Kartica sa ukupnom statistikom: prihod, ukupno termina i razrada po statusu.
class _OverallCard extends StatelessWidget {
  final DetailedReport report;

  const _OverallCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = report.overall;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ukupan prihod', style: theme.textTheme.bodySmall),
                    const SizedBox(height: 4),
                    Text(
                      Format.money(report.totalRevenue),
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Ukupno termina', style: theme.textTheme.bodySmall),
                    const SizedBox(height: 4),
                    Text('${c.total}', style: theme.textTheme.headlineSmall),
                  ],
                ),
              ],
            ),
            const Divider(height: 28),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _StatusChip(
                    label: 'Zakazani', value: c.scheduled, color: Colors.blue),
                _StatusChip(
                    label: 'Završeni', value: c.completed, color: Colors.green),
                _StatusChip(
                    label: 'Otkazani', value: c.cancelled, color: Colors.red),
                _StatusChip(
                    label: 'Nije se pojavio',
                    value: c.noShow,
                    color: Colors.orange),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// KPI kartica: stopa otkazivanja/nedolaska, završenost i prosječan račun.
class _KpiCard extends StatelessWidget {
  final DetailedReport report;

  const _KpiCard({required this.report});

  @override
  Widget build(BuildContext context) {
    String pct(double v) => '${(v * 100).toStringAsFixed(1)}%';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _KpiItem(
                label: 'Završenost',
                value: pct(report.completionRate),
                color: Colors.green),
            _KpiItem(
                label: 'Otkazivanja',
                value: pct(report.cancellationRate),
                color: Colors.red),
            _KpiItem(
                label: 'Nedolasci',
                value: pct(report.noShowRate),
                color: Colors.orange),
            _KpiItem(
                label: 'Prosj. račun',
                value: Format.money(report.averageTicket),
                color: Colors.blue),
          ],
        ),
      ),
    );
  }
}

class _KpiItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _KpiItem(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 2),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// Pita-grafikon razrade statusa + legenda.
class _StatusPieCard extends StatelessWidget {
  final StatusCounts counts;

  const _StatusPieCard({required this.counts});

  @override
  Widget build(BuildContext context) {
    // (naziv, vrijednost, boja) — prikazujemo samo statuse koji postoje.
    final data = <(String, int, Color)>[
      ('Zakazani', counts.scheduled, Colors.blue),
      ('Završeni', counts.completed, Colors.green),
      ('Otkazani', counts.cancelled, Colors.red),
      ('Nije se pojavio', counts.noShow, Colors.orange),
    ].where((e) => e.$2 > 0).toList();

    if (data.isEmpty) {
      return const EmptyView(message: 'Nema podataka za ovaj period.');
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              width: 150,
              height: 150,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 35,
                  sections: [
                    for (final e in data)
                      PieChartSectionData(
                        value: e.$2.toDouble(),
                        color: e.$3,
                        title: '${e.$2}',
                        radius: 40,
                        titleStyle: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 20),
            // Legenda.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final e in data)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                                color: e.$3,
                                borderRadius: BorderRadius.circular(3)),
                          ),
                          const SizedBox(width: 8),
                          Text('${e.$1}  (${e.$2})'),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Stubičasti grafikon prihoda po barberu.
class _BarberRevenueChart extends StatelessWidget {
  final List<BarberReport> barbers;

  const _BarberRevenueChart({required this.barbers});

  @override
  Widget build(BuildContext context) {
    // Prikazujemo najviše 8 barbera (već su sortirani po prihodu).
    final items = barbers.take(8).toList();
    final maxRevenue =
        items.map((b) => b.revenue).fold<double>(0, (a, b) => a > b ? a : b);
    if (maxRevenue <= 0) {
      return const EmptyView(message: 'Nema prihoda za prikaz.');
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 20, 16, 8),
        child: SizedBox(
          height: 220,
          child: BarChart(
            BarChartData(
              maxY: maxRevenue * 1.2,
              barTouchData: BarTouchData(enabled: false),
              borderData: FlBorderData(show: false),
              gridData: const FlGridData(show: true, drawVerticalLine: false),
              titlesData: FlTitlesData(
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: true, reservedSize: 44),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= items.length) {
                        return const SizedBox.shrink();
                      }
                      // Prikazujemo prvo ime barbera (da stane ispod stuba).
                      final name = items[i].name.split(' ').first;
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(name,
                            style: const TextStyle(fontSize: 10),
                            overflow: TextOverflow.ellipsis),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < items.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: items[i].revenue,
                        color: barberColor(items[i].employeeId),
                        width: 18,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4)),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Mali „čip“ statusa: broj + naziv, u boji statusa.
class _StatusChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _StatusChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$value',
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Tabela po barberu: brojevi po statusu + prihod. Horizontalno skrolabilna.
class _BarberTable extends StatelessWidget {
  final DetailedReport report;

  const _BarberTable({required this.report});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Barber')),
            DataColumn(label: Text('Zakazani'), numeric: true),
            DataColumn(label: Text('Završeni'), numeric: true),
            DataColumn(label: Text('Otkazani'), numeric: true),
            DataColumn(label: Text('Nije se pojavio'), numeric: true),
            DataColumn(label: Text('Ukupno'), numeric: true),
            DataColumn(label: Text('Prihod'), numeric: true),
          ],
          rows: [
            for (final b in report.barbers)
              DataRow(cells: [
                DataCell(Text(b.name)),
                DataCell(Text('${b.counts.scheduled}')),
                DataCell(Text('${b.counts.completed}')),
                DataCell(Text('${b.counts.cancelled}')),
                DataCell(Text('${b.counts.noShow}')),
                DataCell(Text('${b.counts.total}')),
                DataCell(Text(Format.money(b.revenue))),
              ]),
            DataRow(cells: [
              const DataCell(
                  Text('UKUPNO', style: TextStyle(fontWeight: FontWeight.bold))),
              DataCell(Text('${report.overall.scheduled}')),
              DataCell(Text('${report.overall.completed}')),
              DataCell(Text('${report.overall.cancelled}')),
              DataCell(Text('${report.overall.noShow}')),
              DataCell(Text('${report.overall.total}')),
              DataCell(Text(
                Format.money(report.totalRevenue),
                style: const TextStyle(fontWeight: FontWeight.bold),
              )),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Tabela po usluzi: broj termina + prihod.
class _ServiceTable extends StatelessWidget {
  final List<ServiceReport> services;

  const _ServiceTable({required this.services});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Usluga')),
            DataColumn(label: Text('Broj'), numeric: true),
            DataColumn(label: Text('Prihod'), numeric: true),
          ],
          rows: [
            for (final s in services)
              DataRow(cells: [
                DataCell(Text(s.name)),
                DataCell(Text('${s.count}')),
                DataCell(Text(Format.money(s.revenue))),
              ]),
          ],
        ),
      ),
    );
  }
}

/// Jedan red u „mini grafikonu“ prihoda — datum, traka i iznos.
class _RevenueBar extends StatelessWidget {
  final RevenueBucket bucket;
  final double maxRevenue;

  const _RevenueBar({required this.bucket, required this.maxRevenue});

  @override
  Widget build(BuildContext context) {
    final fraction = maxRevenue == 0 ? 0.0 : bucket.revenue / maxRevenue;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(Format.date(bucket.bucketStart),
                style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 16,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(
              Format.money(bucket.revenue),
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Pomoćne funkcije za CSV export ----

String _fileDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
String _two(int n) => n.toString().padLeft(2, '0');
String _csvMoney(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

/// Sastavlja CSV tekst iz detaljnog izvještaja. Separator je „;“.
String _buildCsv(DetailedReport r, DateTimeRange range) {
  final b = StringBuffer();
  b.writeln('Izvještaj salona');
  b.writeln('Period;${Format.date(range.start)} - ${Format.date(range.end)}');
  b.writeln();

  b.writeln('UKUPNO');
  b.writeln('Status;Broj');
  b.writeln('Zakazani;${r.overall.scheduled}');
  b.writeln('Završeni;${r.overall.completed}');
  b.writeln('Otkazani;${r.overall.cancelled}');
  b.writeln('Nije se pojavio;${r.overall.noShow}');
  b.writeln('Ukupno termina;${r.overall.total}');
  b.writeln('Ukupan prihod (EUR);${_csvMoney(r.totalRevenue)}');
  b.writeln('Prosjecan racun (EUR);${_csvMoney(r.averageTicket)}');
  b.writeln();

  b.writeln('PO BARBERU');
  b.writeln(
      'Barber;Zakazani;Završeni;Otkazani;Nije se pojavio;Ukupno;Prihod (EUR)');
  for (final br in r.barbers) {
    b.writeln('${br.name};${br.counts.scheduled};${br.counts.completed};'
        '${br.counts.cancelled};${br.counts.noShow};${br.counts.total};'
        '${_csvMoney(br.revenue)}');
  }
  b.writeln();

  b.writeln('PO USLUZI');
  b.writeln('Usluga;Broj;Prihod (EUR)');
  for (final s in r.services) {
    b.writeln('${s.name};${s.count};${_csvMoney(s.revenue)}');
  }
  return b.toString();
}
