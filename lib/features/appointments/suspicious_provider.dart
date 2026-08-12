import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../services/providers.dart';

/// Prag (u satima) za „sumnjiv" termin: koliko NAKON vremena termina je zakazan.
/// Default 4 (kao i backend).
final suspiciousMinGapProvider = StateProvider<int>((ref) => 4);

/// Lista sumnjivih (retroaktivno zakazanih) termina. Razriješeni se ne vraćaju.
final suspiciousProvider =
    FutureProvider.autoDispose<List<AppointmentResponse>>((ref) {
  final gap = ref.watch(suspiciousMinGapProvider);
  return ref
      .watch(apiServiceProvider)
      .getSuspiciousAppointments(minGapHours: gap);
});
