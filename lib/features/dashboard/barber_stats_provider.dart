import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../services/providers.dart';
import '../appointments/day_schedule_provider.dart';

/// Kratka statistika dana za prijavljenog barbera (za početnu stranu).
class BarberTodayStats {
  final int total; // svi termini danas (osim otkazanih i pauza)
  final int completed; // završeni
  final int upcoming; // preostali zakazani (još nijesu počeli)
  final DateTime? nextStart; // vrijeme sljedećeg termina (ako postoji)

  const BarberTodayStats({
    required this.total,
    required this.completed,
    required this.upcoming,
    required this.nextStart,
  });
}

/// Učitava današnje termine prijavljenog barbera i računa kratku statistiku.
/// Server za ne-admina vraća samo njegove termine (ne šaljemo employeeId).
final barberTodayStatsProvider =
    FutureProvider.autoDispose<BarberTodayStats>((ref) async {
  final api = ref.watch(apiServiceProvider);
  final now = DateTime.now();
  final dayStart = DateTime(now.year, now.month, now.day);
  final dayEnd = dayStart.add(const Duration(days: 1));

  final page = await api.getAppointments(
    from: dayStart.toUtc().toIso8601String(),
    to: dayEnd.toUtc().toIso8601String(),
    page: 0,
    size: 200,
    sort: 'startTime,asc',
  );

  // Bez otkazanih i bez pauza (pauze nisu „pravi“ termini).
  final appts = page.content
      .where((a) => a.status != AppointmentStatus.cancelled)
      .where((a) => !isBreakNote(a.note))
      .toList();

  final completed =
      appts.where((a) => a.status == AppointmentStatus.completed).length;

  var upcoming = 0;
  DateTime? next;
  for (final a in appts) {
    final s = a.startTime?.toLocal();
    if (a.status == AppointmentStatus.scheduled &&
        s != null &&
        s.isAfter(now)) {
      upcoming++;
      next ??= s; // prvi (lista je sortirana po vremenu)
    }
  }

  return BarberTodayStats(
    total: appts.length,
    completed: completed,
    upcoming: upcoming,
    nextStart: next,
  );
});
