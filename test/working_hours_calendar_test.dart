import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:salon_management/features/shifts/working_hours_calendar_tab.dart';
import 'package:salon_management/features/shifts/working_hours_overrides_provider.dart';
import 'package:salon_management/services/api_service.dart';
import 'package:salon_management/services/providers.dart';

Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiServiceProvider.overrideWithValue(ApiService(Dio())),
      ],
      child: const MaterialApp(
        home: Scaffold(body: WorkingHoursCalendarTab()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('Kalendar radnog vremena — širok, bez layout greške',
      (tester) async {
    await _pump(tester, const Size(1100, 750));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Kalendar radnog vremena — uzak, bez layout greške',
      (tester) async {
    await _pump(tester, const Size(400, 780));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Kalendar radnog vremena — uzak + izabran dan (3 dugmeta)',
      (tester) async {
    await _pump(tester, const Size(400, 780));
    await tester.tap(find.text('15')); // izaberi 15. u mjesecu
    await tester.pump();
    expect(find.text('Postavi vrijeme'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Kalendar radnog vremena — vrlo nizak, bez layout greške',
      (tester) async {
    await _pump(tester, const Size(360, 600));
    expect(tester.takeException(), isNull);
  });

  test('selectRange izabere sve dane između sidra i cilja', () {
    final c = ProviderContainer(overrides: [
      apiServiceProvider.overrideWithValue(ApiService(Dio())),
    ]);
    c.listen(workingHoursCalendarProvider, (_, __) {});
    addTearDown(c.dispose);

    final ctrl = c.read(workingHoursCalendarProvider.notifier);
    ctrl.toggleDay('2026-08-04');
    ctrl.selectRange('2026-08-07');

    expect(c.read(workingHoursCalendarProvider).selectedDays,
        {'2026-08-04', '2026-08-05', '2026-08-06', '2026-08-07'});
  });
}
