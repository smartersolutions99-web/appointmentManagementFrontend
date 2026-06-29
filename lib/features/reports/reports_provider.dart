import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../services/providers.dart';
import '../appointments/day_schedule_provider.dart' show isBreakNote;
import '../employees/employees_provider.dart';
import '../services/services_provider.dart';

/// Izabrani vremenski raspon za izvještaje. Podrazumijevano: posljednjih 30 dana.
///
/// `StateProvider` drži jednostavnu promjenljivu vrijednost koju mijenjamo
/// iz UI-a (npr. kad korisnik izabere drugi period).
final reportRangeProvider = StateProvider<DateTimeRange>((ref) {
  final now = DateTime.now();
  return DateTimeRange(
    start: now.subtract(const Duration(days: 30)),
    end: now,
  );
});

/// Pretvara DateTime u ISO tekst koji server očekuje (npr. za query parametre).
///
/// VAŽNO: server traži vrijeme sa oznakom zone (npr. „...Z“). Zato prvo
/// pretvaramo u UTC — `toUtc().toIso8601String()` daje npr. „2026-05-17T21:13:20.924Z“.
/// Bez ovoga (čisto lokalno vrijeme bez zone) server vraća grešku 400.
String _iso(DateTime dt) => dt.toUtc().toIso8601String();

/// Prihod salona za posljednjih 30 dana — za početnu stranu.
///
/// NAMJERNO ne zavisi od `reportRangeProvider` (koji se mijenja na ekranu
/// Izvještaji), pa biranje perioda tamo NE utiče na početnu stranu.
final last30DaysRevenueProvider = FutureProvider<RevenueSummary>((ref) {
  final now = DateTime.now();
  final from = now.subtract(const Duration(days: 30));
  return ref.watch(apiServiceProvider).shopRevenue(
        from: _iso(from),
        to: _iso(now),
      );
});

/// Prihod kroz vrijeme (po danima) — za jednostavan prikaz trenda.
final revenueOverTimeProvider = FutureProvider<List<RevenueBucket>>((ref) {
  final range = ref.watch(reportRangeProvider);
  return ref.watch(apiServiceProvider).revenueOverTime(
        from: _iso(range.start),
        to: _iso(range.end),
        bucket: 'day',
      );
});

// ===================== DETALJNA STATISTIKA (statusi + finansije) =====================

/// Broj termina po statusu (za ukupnu statistiku ili po barberu).
class StatusCounts {
  final int scheduled;
  final int completed;
  final int cancelled;
  final int noShow;

  const StatusCounts({
    this.scheduled = 0,
    this.completed = 0,
    this.cancelled = 0,
    this.noShow = 0,
  });

  int get total => scheduled + completed + cancelled + noShow;
}

/// Statistika jednog barbera: nazivi + brojevi po statusu + ostvareni prihod.
class BarberReport {
  final int? employeeId;
  final String name;
  final StatusCounts counts;
  final double revenue; // suma cijena ZAVRŠENIH termina

  const BarberReport({
    required this.employeeId,
    required this.name,
    required this.counts,
    required this.revenue,
  });
}

/// Statistika jedne usluge: koliko puta je rađena i koliki prihod je donijela.
class ServiceReport {
  final int? serviceId;
  final String name;
  final int count; // broj termina sa ovom uslugom (osim otkazanih/nedolaska)
  final double revenue; // prihod od završenih

  const ServiceReport({
    required this.serviceId,
    required this.name,
    required this.count,
    required this.revenue,
  });
}

/// Cjelokupan detaljan izvještaj za period: ukupno + po barberu + po usluzi.
class DetailedReport {
  final StatusCounts overall;
  final double totalRevenue;
  final List<BarberReport> barbers;
  final List<ServiceReport> services;

  const DetailedReport({
    required this.overall,
    required this.totalRevenue,
    required this.barbers,
    required this.services,
  });

  /// Pomoćni KPI pokazatelji (u procentima / prosjek).
  double get cancellationRate =>
      overall.total == 0 ? 0 : overall.cancelled / overall.total;
  double get noShowRate =>
      overall.total == 0 ? 0 : overall.noShow / overall.total;
  double get completionRate =>
      overall.total == 0 ? 0 : overall.completed / overall.total;
  double get averageTicket =>
      overall.completed == 0 ? 0 : totalRevenue / overall.completed;
}

/// Pomoćni sabirač (interno) — broji statuse i sabira prihod.
class _Acc {
  int scheduled = 0, completed = 0, cancelled = 0, noShow = 0;
  double revenue = 0;

  void add(AppointmentStatus status, double price) {
    switch (status) {
      case AppointmentStatus.scheduled:
        scheduled++;
      case AppointmentStatus.completed:
        completed++;
        revenue += price; // prihod priznajemo tek kad je termin završen
      case AppointmentStatus.cancelled:
        cancelled++;
      case AppointmentStatus.noShow:
        noShow++;
    }
  }

  StatusCounts get counts => StatusCounts(
        scheduled: scheduled,
        completed: completed,
        cancelled: cancelled,
        noShow: noShow,
      );
}

/// Učitava SVE termine u izabranom periodu (kroz stranice) i računa detaljnu
/// statistiku: brojeve po statusu (ukupno i po barberu) i ostvareni prihod.
/// Pauze se preskaču (nisu pravi termini).
final detailedReportProvider =
    FutureProvider.autoDispose<DetailedReport>((ref) async {
  final api = ref.watch(apiServiceProvider);
  final range = ref.watch(reportRangeProvider);
  final from = _iso(range.start);
  final to = _iso(range.end);

  // Učitaj sve stranice termina za period.
  final all = <AppointmentResponse>[];
  var page = 0;
  while (true) {
    final p = await api.getAppointments(
      from: from,
      to: to,
      page: page,
      size: 200,
      sort: 'startTime,asc',
    );
    all.addAll(p.content);
    if (p.last || p.content.isEmpty) break;
    page++;
    if (page > 100) break; // sigurnosna granica protiv beskonačne petlje
  }

  // Imena barbera.
  final employees = await ref.watch(employeesProvider.future);
  final nameById = {for (final e in employees) e.id: e.name};

  // Imena usluga (ako ne uspije, koristimo ID).
  List<ServiceEntityResponse> services;
  try {
    services = await ref.watch(servicesProvider.future);
  } catch (_) {
    services = const [];
  }
  final serviceNameById = {for (final s in services) s.id: s.name};

  // Saberi ukupno, po barberu i po usluzi.
  final overall = _Acc();
  final byBarber = <int?, _Acc>{};
  final byService = <int?, _Acc>{};
  for (final a in all) {
    if (isBreakNote(a.note)) continue; // pauze ne ulaze u statistiku
    final status = a.status ?? AppointmentStatus.scheduled;
    final price = a.servicePrice ?? 0;
    overall.add(status, price);
    byBarber.putIfAbsent(a.employeeId, () => _Acc()).add(status, price);
    // Otkazane i nedolaske ne brojimo kao „rađenu uslugu“.
    if (status != AppointmentStatus.cancelled &&
        status != AppointmentStatus.noShow) {
      byService.putIfAbsent(a.serviceId, () => _Acc()).add(status, price);
    }
  }

  final barbers = [
    for (final entry in byBarber.entries)
      BarberReport(
        employeeId: entry.key,
        name: nameById[entry.key] ?? 'Zaposleni ${entry.key ?? '-'}',
        counts: entry.value.counts,
        revenue: entry.value.revenue,
      ),
  ]..sort((a, b) => b.revenue.compareTo(a.revenue));

  final serviceReports = [
    for (final entry in byService.entries)
      ServiceReport(
        serviceId: entry.key,
        name: serviceNameById[entry.key] ?? 'Bez usluge',
        count: entry.value.counts.total,
        revenue: entry.value.revenue,
      ),
  ]..sort((a, b) => b.count.compareTo(a.count));

  return DetailedReport(
    overall: overall.counts,
    totalRevenue: overall.revenue,
    barbers: barbers,
    services: serviceReports,
  );
});
