import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/exceptions.dart';
import '../../models/models.dart';
import '../../services/providers.dart';
import '../../shared/file_download.dart';
import '../../shared/format.dart';
import '../../shared/widgets.dart';
import '../appointments/barber_colors.dart';
import '../appointments/day_schedule_provider.dart'
    show isBreakNote, customerDirectoryProvider;
import '../employees/employees_provider.dart';
import '../services/services_provider.dart';
import 'report_export.dart';
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

  /// Sastavi zbirni .xlsx (Ukupno + Po uslugama + sheet po zaposlenom) i pokreni
  /// preuzimanje/čuvanje. Web: browser preuzima fajl. Desktop: snima u Downloads.
  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final report = ref.read(detailedReportProvider).value;
    final range = ref.read(reportRangeProvider);
    if (report == null) {
      showSnack(context, 'Sačekajte da se izvještaj učita.', isError: true);
      return;
    }
    try {
      final bytes = buildSummaryWorkbook(report, range);
      final name =
          'izvjestaj_${_fileDate(range.start)}_${_fileDate(range.end)}.xlsx';
      final path = await downloadBytesFile(name, bytes);
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

  /// „Detaljni izvještaj": .xlsx sa SVIM terminima (svi podaci) za izabrane
  /// zaposlene i tekući period. Prvo bira zaposlene, pa učita i sastavi fajl.
  Future<void> _exportDetailed(BuildContext context, WidgetRef ref) async {
    // Lista zaposlenih (za izbor kojih uključiti).
    List<EmployeeResponse> employees;
    try {
      employees = await ref.read(employeesProvider.future);
    } catch (e) {
      if (context.mounted) {
        showSnack(context, ApiException.from(e).message, isError: true);
      }
      return;
    }
    if (!context.mounted) return;
    if (employees.isEmpty) {
      showSnack(context, 'Nema zaposlenih.', isError: true);
      return;
    }

    // Izbor zaposlenih (podrazumijevano svi). Vraća listu id-jeva ili null (otkaz).
    final selected = await showDialog<List<int>>(
      context: context,
      builder: (_) => _EmployeePickerDialog(employees: employees),
    );
    if (selected == null || selected.isEmpty) return;

    // Blokirajući indikator dok se učitava i sastavlja (može potrajati par sekundi).
    if (!context.mounted) return;
    // Zapamti messenger i ROOT navigator PRIJE async posla — `showDialog` gura
    // dijalog na root navigator, pa ga i zatvaramo preko njega (inače bi se
    // zatvorio pogrešan ekran i aplikacija bi prijavila grešku).
    final messenger = ScaffoldMessenger.of(context);
    final rootNav = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    var progressOpen = true;
    void closeProgress() {
      if (progressOpen) {
        progressOpen = false;
        rootNav.pop();
      }
    }

    try {
      final range = ref.read(reportRangeProvider);
      final rows = await _fetchDetailedRows(ref, range, selected.toSet());
      final bytes = buildDetailedWorkbook(rows, range: range);
      final name =
          'termini_detaljno_${_fileDate(range.start)}_${_fileDate(range.end)}.xlsx';
      final path = await downloadBytesFile(name, bytes);
      closeProgress();
      messenger.showSnackBar(SnackBar(
        content: Text(
          path != null
              ? 'Sačuvano: $path (${rows.length} termina)'
              : 'Izvještaj preuzet: $name (${rows.length} termina)',
        ),
      ));
    } catch (e) {
      closeProgress();
      messenger.showSnackBar(SnackBar(
        content: Text('Greška pri exportu: ${ApiException.from(e).message}'),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  /// Učita sve termine za period, spoji imena (barber/klijent/usluga) i vrati
  /// redove za izabrane zaposlene. Pauze se preskaču.
  Future<List<DetailedApptRow>> _fetchDetailedRows(
    WidgetRef ref,
    DateTimeRange range,
    Set<int> employeeIds,
  ) async {
    final api = ref.read(apiServiceProvider);

    // Svi termini u periodu (kroz stranice).
    final all = <AppointmentResponse>[];
    var page = 0;
    while (true) {
      final p = await api.getAppointments(
        from: range.start.toUtc().toIso8601String(),
        to: range.end.toUtc().toIso8601String(),
        page: page,
        size: 200,
        sort: 'startTime,asc',
      );
      all.addAll(p.content);
      if (p.last || p.content.isEmpty) break;
      page++;
      if (page > 100) break;
    }

    // Imena barbera.
    final employees = await ref.read(employeesProvider.future);
    final nameById = {for (final e in employees) e.id: e.name};

    // Imena usluga (ako ne uspije — bez naziva).
    List<ServiceEntityResponse> services;
    try {
      services = await ref.read(servicesProvider.future);
    } catch (_) {
      services = const [];
    }
    final serviceNameById = {for (final s in services) s.id: s.name};

    // Adresar klijenata (ime + telefon) — ako ne uspije, koristimo podatke sa termina.
    List<CustomerResponse> customers;
    try {
      customers = await ref.read(customerDirectoryProvider.future);
    } catch (_) {
      customers = const [];
    }
    final customerById = {for (final c in customers) c.id: c};

    final rows = <DetailedApptRow>[];
    for (final a in all) {
      if (isBreakNote(a.note)) continue; // pauze nisu pravi termini
      if (a.employeeId == null || !employeeIds.contains(a.employeeId)) continue;
      final start = a.startTime?.toLocal();
      final end = a.endTime?.toLocal() ??
          (start != null && a.duration != null
              ? start.add(Duration(minutes: a.duration!))
              : null);
      final cust = a.customerId != null ? customerById[a.customerId] : null;
      rows.add(DetailedApptRow(
        employeeId: a.employeeId,
        start: start,
        end: end,
        barber: nameById[a.employeeId] ?? 'Zaposleni ${a.employeeId}',
        customer: a.customerName ?? cust?.name ?? '',
        phone: a.customerPhone ?? cust?.contactValue ?? '',
        service: serviceNameById[a.serviceId] ?? '',
        price: a.servicePrice ?? 0,
        duration: a.duration,
        status: a.status ?? AppointmentStatus.scheduled,
        note: a.note ?? '',
      ));
    }
    return rows;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(reportRangeProvider);
    final detailedAsync = ref.watch(detailedReportProvider);
    final trendAsync = ref.watch(revenueOverTimeProvider);
    // „Budući termini" gledamo NA NIVOU EKRANA (ne samo unutar sekcije) da
    // provider ostane živ dok skrolamo — inače se (autoDispose) svaki put pri
    // povratku u vidokrug ponovo učita (makazice). Ekran ostaje živ dok smo na
    // stranici, pa se učita jednom.
    final upcomingAsync = ref.watch(upcomingReportProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ---- Budući (zakazani) termini ----
        _UpcomingSection(reportAsync: upcomingAsync),
        const Divider(height: 40),

        // ---- Ostvareno (izabrani prošli period) ----
        Text('Ostvareno (izabrani period)',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
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
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _exportDetailed(context, ref),
                icon: const Icon(Icons.list_alt),
                label: const Text('Detaljni izvještaj'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _export(context, ref),
                icon: const Icon(Icons.download),
                label: const Text('Izvezi u Excel'),
              ),
            ],
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
              const SizedBox(height: 24),

              // Statistika po klijentu (rang liste).
              Text('Po klijentu',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (report.customers.isEmpty)
                const EmptyView(message: 'Nema podataka za ovaj period.')
              else
                _TopCustomers(customers: report.customers),
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

// ===================== BUDUĆI TERMINI (sekcija) =====================

/// „Sljedeći termin" kratko: „27.07. 10:00" (ili „—").
String _nextLabel(DateTime? d) =>
    d == null ? '—' : '${_two(d.day)}.${_two(d.month)}. ${Format.time(d)}';

/// Sekcija „Budući termini": izbor budućeg perioda + zbir + tabela po barberu.
class _UpcomingSection extends ConsumerWidget {
  final AsyncValue<UpcomingReport> reportAsync;
  const _UpcomingSection({required this.reportAsync});

  Future<void> _pickRange(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final current = ref.read(upcomingRangeProvider);
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: current,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 1, 12, 31), // budući datumi dozvoljeni
    );
    if (picked != null) {
      ref.read(upcomingRangeProvider.notifier).state = picked;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final range = ref.watch(upcomingRangeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Budući termini (zakazano)', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        const _UpcomingPeriods(),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.event_available),
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
        const SizedBox(height: 12),
        AsyncValueView<UpcomingReport>(
          value: reportAsync,
          onRetry: () => ref.invalidate(upcomingReportProvider),
          data: (r) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _UpcomingSummaryCard(report: r),
              const SizedBox(height: 12),
              if (r.barbers.isEmpty)
                const EmptyView(
                    message: 'Nema zakazanih termina u ovom periodu.')
              else
                _ReportTable(
                  headers: const [
                    'Barber',
                    'Zakazano',
                    'Očekivano',
                    'Sljedeći',
                  ],
                  rows: [
                    for (final b in r.barbers)
                      [
                        b.name,
                        '${b.scheduled}',
                        Format.money(b.expectedRevenue),
                        _nextLabel(b.nextStart),
                      ],
                    [
                      'UKUPNO',
                      '${r.totalScheduled}',
                      Format.money(r.expectedRevenue),
                      '',
                    ],
                  ],
                  boldRows: {r.barbers.length}, // posljednji red = UKUPNO
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Brzi izbor budućeg perioda.
class _UpcomingPeriods extends ConsumerWidget {
  const _UpcomingPeriods();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void set(DateTimeRange r) =>
        ref.read(upcomingRangeProvider.notifier).state = r;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Wrap(
      spacing: 8,
      children: [
        ActionChip(
          label: const Text('Sljedećih 7 dana'),
          onPressed: () => set(
              DateTimeRange(start: today, end: today.add(const Duration(days: 7)))),
        ),
        ActionChip(
          label: const Text('Sljedećih 30 dana'),
          onPressed: () => set(DateTimeRange(
              start: today, end: today.add(const Duration(days: 30)))),
        ),
        ActionChip(
          label: const Text('Sljedeći mjesec'),
          onPressed: () => set(DateTimeRange(
            start: DateTime(now.year, now.month + 1, 1),
            end: DateTime(now.year, now.month + 2, 1),
          )),
        ),
      ],
    );
  }
}

/// Zbirna kartica budućih termina: ukupno zakazano + očekivani prihod + najprometniji dan.
class _UpcomingSummaryCard extends StatelessWidget {
  final UpcomingReport report;

  const _UpcomingSummaryCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busiest = report.busiestDay;

    Widget stat(String label, String value) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(value,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ],
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                stat('Zakazano ukupno', '${report.totalScheduled}'),
                stat('Očekivani prihod', Format.money(report.expectedRevenue)),
              ],
            ),
            if (busiest != null) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(Icons.local_fire_department_outlined,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Najprometniji dan: ${Format.date(busiest.key)} '
                      '(${busiest.value} ${busiest.value == 1 ? 'termin' : 'termina'})',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
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

/// Tabela po barberu: brojevi po statusu + prihod + procenat i ostatak salonu.
class _BarberTable extends StatelessWidget {
  final DetailedReport report;

  const _BarberTable({required this.report});

  @override
  Widget build(BuildContext context) {
    // Zbir „ostaje salonu" po svim barberima (za red UKUPNO).
    final totalSalonKeep =
        report.barbers.fold<double>(0, (s, b) => s + b.salonKeep);

    return _ReportTable(
      headers: const [
        'Barber',
        'Zakazani',
        'Završeni',
        'Otkazani',
        'Nije se pojavio',
        'Ukupno',
        'Prihod',
        'Procenat',
        'Ostaje salonu',
      ],
      rows: [
        for (final b in report.barbers)
          [
            b.name,
            '${b.counts.scheduled}',
            '${b.counts.completed}',
            '${b.counts.cancelled}',
            '${b.counts.noShow}',
            '${b.counts.total}',
            Format.money(b.revenue),
            _pctLabel(b.commission),
            Format.money(b.salonKeep),
          ],
        [
          'UKUPNO',
          '${report.overall.scheduled}',
          '${report.overall.completed}',
          '${report.overall.cancelled}',
          '${report.overall.noShow}',
          '${report.overall.total}',
          Format.money(report.totalRevenue),
          '',
          Format.money(totalSalonKeep),
        ],
      ],
      boldRows: {report.barbers.length}, // posljednji red = UKUPNO
    );
  }
}

/// Sekcija „Po klijentu": tri rang-liste (najviše dolazi / najviše potrošio /
/// najviše otkazivao). Svaka pokazuje do 5 klijenata.
class _TopCustomers extends StatelessWidget {
  final List<CustomerReport> customers;

  const _TopCustomers({required this.customers});

  List<CustomerReport> _topByInt(int Function(CustomerReport) metric) {
    final list = customers.where((c) => metric(c) > 0).toList()
      ..sort((a, b) => metric(b).compareTo(metric(a)));
    return list.take(5).toList();
  }

  @override
  Widget build(BuildContext context) {
    final byVisits = _topByInt((c) => c.visits);
    final byMissed = _topByInt((c) => c.missed);
    final bySpent = (customers.where((c) => c.spent > 0).toList()
          ..sort((a, b) => b.spent.compareTo(a.spent)))
        .take(5)
        .toList();

    return Column(
      children: [
        _rankCard(context, 'Najviše dolazi', Icons.emoji_events_outlined,
            Colors.green, byVisits, (c) => '${c.visits}'),
        const SizedBox(height: 8),
        _rankCard(context, 'Najviše potrošio', Icons.payments_outlined,
            Colors.blue, bySpent, (c) => Format.money(c.spent)),
        const SizedBox(height: 8),
        _rankCard(
            context,
            'Najviše otkazivao / nije dolazio',
            Icons.event_busy_outlined,
            Colors.red,
            byMissed,
            (c) => '${c.missed}'),
      ],
    );
  }

  Widget _rankCard(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    List<CustomerReport> items,
    String Function(CustomerReport) valueOf,
  ) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Text(title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text('—', style: theme.textTheme.bodySmall),
              )
            else
              for (var i = 0; i < items.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 22,
                        child: Text('${i + 1}.',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.hintColor)),
                      ),
                      Expanded(
                        child: Text(items[i].name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      Text(valueOf(items[i]),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
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
    return _ReportTable(
      headers: const ['Usluga', 'Broj', 'Prihod'],
      rows: [
        for (final s in services)
          [s.name, '${s.count}', Format.money(s.revenue)],
      ],
    );
  }
}

/// Tabela izvještaja. Na uskom ekranu (telefon) prva kolona je „zamrznuta"
/// (uvijek vidljiva) dok se ostale skroluju vodoravno; na širem ekranu je
/// obična tabela (vodoravni skrol ako ne stane).
class _ReportTable extends StatelessWidget {
  final List<String> headers; // headers.first = zamrznuta kolona
  final List<List<String>> rows; // svaki red: ćelije po redoslijedu headers
  final Set<int> boldRows; // indeksi redova koje treba podebljati (npr. UKUPNO)

  const _ReportTable({
    required this.headers,
    required this.rows,
    this.boldRows = const {},
  });

  // Iste visine na obje strane → redovi poravnati kad je kolona zamrznuta.
  static const double _headH = 48;
  static const double _rowH = 46;

  TextStyle? _style(int r) =>
      boldRows.contains(r) ? const TextStyle(fontWeight: FontWeight.bold) : null;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) =>
          c.maxWidth < 600 ? _sticky(context) : _plain(context),
    );
  }

  /// Široko: jedna obična tabela.
  Widget _plain(BuildContext context) {
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [
            for (var i = 0; i < headers.length; i++)
              DataColumn(label: Text(headers[i]), numeric: i > 0),
          ],
          rows: [
            for (var r = 0; r < rows.length; r++)
              DataRow(cells: [
                for (var i = 0; i < headers.length; i++)
                  DataCell(Text(rows[r][i], style: _style(r))),
              ]),
          ],
        ),
      ),
    );
  }

  /// Usko: prva kolona fiksna lijevo, ostale u vodoravnom skrolu.
  Widget _sticky(BuildContext context) {
    final theme = Theme.of(context);

    final frozen = DataTable(
      headingRowHeight: _headH,
      dataRowMinHeight: _rowH,
      dataRowMaxHeight: _rowH,
      horizontalMargin: 12,
      columnSpacing: 0,
      columns: [DataColumn(label: Text(headers.first))],
      rows: [
        for (var r = 0; r < rows.length; r++)
          DataRow(cells: [
            DataCell(ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 130),
              child: Text(rows[r].first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _style(r)),
            )),
          ]),
      ],
    );

    final scrollable = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: _headH,
        dataRowMinHeight: _rowH,
        dataRowMaxHeight: _rowH,
        columns: [
          for (var i = 1; i < headers.length; i++)
            DataColumn(label: Text(headers[i]), numeric: true),
        ],
        rows: [
          for (var r = 0; r < rows.length; r++)
            DataRow(cells: [
              for (var i = 1; i < headers.length; i++)
                DataCell(Text(rows[r][i], style: _style(r))),
            ]),
        ],
      ),
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Zamrznuta prva kolona + tanka linija razdvajanja.
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: theme.dividerColor)),
            ),
            child: frozen,
          ),
          Expanded(child: scrollable),
        ],
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

// ---- Pomoćne funkcije za export ----

String _fileDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
String _two(int n) => n.toString().padLeft(2, '0');

/// Procenat za prikaz: „50%" (cijeli broj) ili „—" kad nije podešen.
String _pctLabel(double? c) {
  if (c == null) return '—';
  return c % 1 == 0 ? '${c.toInt()}%' : '${c.toStringAsFixed(1)}%';
}

/// Dijalog za izbor zaposlenih za „Detaljni izvještaj". Podrazumijevano su svi
/// izabrani. Vraća listu id-jeva (ili `null` na otkaz).
class _EmployeePickerDialog extends StatefulWidget {
  final List<EmployeeResponse> employees;

  const _EmployeePickerDialog({required this.employees});

  @override
  State<_EmployeePickerDialog> createState() => _EmployeePickerDialogState();
}

class _EmployeePickerDialogState extends State<_EmployeePickerDialog> {
  late final Set<int> _selected;

  @override
  void initState() {
    super.initState();
    // Podrazumijevano: svi zaposleni izabrani.
    _selected = {
      for (final e in widget.employees)
        if (e.id != null) e.id!,
    };
  }

  bool get _allSelected => _selected.length ==
      widget.employees.where((e) => e.id != null).length;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Detaljni izvještaj — zaposleni'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Izaberite za koje zaposlene se pravi izvještaj.'),
            const SizedBox(height: 8),
            // „Svi zaposleni" prekidač (čekiraj/odčekiraj sve).
            CheckboxListTile(
              dense: true,
              value: _allSelected,
              title: const Text('Svi zaposleni',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              onChanged: (v) => setState(() {
                _selected.clear();
                if (v ?? false) {
                  for (final e in widget.employees) {
                    if (e.id != null) _selected.add(e.id!);
                  }
                }
              }),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final e in widget.employees)
                    if (e.id != null)
                      CheckboxListTile(
                        dense: true,
                        value: _selected.contains(e.id),
                        title: Text(e.name ?? 'Zaposleni ${e.id}'),
                        onChanged: (v) => setState(() {
                          if (v ?? false) {
                            _selected.add(e.id!);
                          } else {
                            _selected.remove(e.id!);
                          }
                        }),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Otkaži'),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(context, _selected.toList()),
          child: const Text('Generiši'),
        ),
      ],
    );
  }
}
