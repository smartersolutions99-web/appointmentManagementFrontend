import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:salon_management/features/employees/employees_provider.dart';
import 'package:salon_management/features/shifts/shift_assignments_provider.dart';
import 'package:salon_management/features/shifts/shift_assignments_screen.dart';
import 'package:salon_management/models/models.dart';
import 'package:salon_management/services/api_service.dart';
import 'package:salon_management/services/providers.dart';

/// Renderuje ekran „Dodjela smjena" i provjerava da NEMA layout greške.
Future<void> _pumpScreen(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Bez pravog servera — pozivi padnu, kontroler uhvati grešku.
        apiServiceProvider.overrideWithValue(ApiService(Dio())),
        employeesProvider.overrideWith((ref) async => const [
              EmployeeResponse(id: 1, name: 'Marko'),
              EmployeeResponse(id: 2, name: 'Ana'),
            ]),
        allShiftTemplatesProvider
            .overrideWith((ref) async => const <ShiftTemplateResponse>[]),
      ],
      child: const MaterialApp(
        home: Scaffold(body: ShiftAssignmentsScreen()),
      ),
    ),
  );

  await tester.pump(); // prvi frame
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('Dodjela smjena — širok ekran, bez layout greške', (tester) async {
    await _pumpScreen(tester, const Size(1100, 750));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Dodjela smjena — uzak ekran, bez layout greške', (tester) async {
    await _pumpScreen(tester, const Size(400, 780));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Dodjela smjena — vrlo nizak ekran, bez layout greške',
      (tester) async {
    await _pumpScreen(tester, const Size(360, 600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Dodjela smjena — uzak + izabran barber (dugmad vidljiva)',
      (tester) async {
    await _pumpScreen(tester, const Size(400, 780));
    // Izaberi barbera → pojave se dugmad u donjoj traci (bivši uzrok prelijevanja).
    await tester.tap(find.text('Marko'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Dodijeli smjenu'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
