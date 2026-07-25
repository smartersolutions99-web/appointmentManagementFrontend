import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:salon_management/features/appointments/day_schedule_provider.dart';
import 'package:salon_management/models/models.dart';

/// Provjera logike „salon ne radi ovog dana" (koristi se da se na zatvoren dan
/// ne nudi zakazivanje). Override-ujemo dayScheduleInfoProvider (izvor iz
/// `/api/schedule`) i provjeravamo izvedeni salonClosedForDayProvider.
Future<bool> _closed(ScheduleDayResponse? sched) async {
  final c = ProviderContainer(overrides: [
    dayScheduleInfoProvider.overrideWith((ref) async => sched),
  ]);
  addTearDown(c.dispose);
  return c.read(salonClosedForDayProvider.future);
}

void main() {
  test('zatvoreno kad salonOpensAt/closesAt == null', () async {
    expect(
      await _closed(const ScheduleDayResponse(
          date: '2026-08-15', salonOpensAt: null, salonClosesAt: null)),
      isTrue,
    );
  });

  test('otvoreno kad ima radno vrijeme', () async {
    expect(
      await _closed(const ScheduleDayResponse(
          date: '2026-08-10',
          salonOpensAt: '08:00:00',
          salonClosesAt: '20:00:00')),
      isFalse,
    );
  });

  test('ne blokira kad raspored nije dostupan (null)', () async {
    expect(await _closed(null), isFalse);
  });
}
