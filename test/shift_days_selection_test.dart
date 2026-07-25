import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:salon_management/features/shifts/shift_days_provider.dart';
import 'package:salon_management/services/api_service.dart';
import 'package:salon_management/services/providers.dart';

/// Napravi kontroler bez pravog servera (load() padne, ali logika izbora radi).
ShiftDaysController _controller(ProviderContainer c) =>
    c.read(shiftDaysControllerProvider.notifier);

ProviderContainer _container() {
  final c = ProviderContainer(overrides: [
    apiServiceProvider.overrideWithValue(ApiService(Dio())),
  ]);
  // Drži `autoDispose` provider živim tokom testa (inače se ugasi bez slušaoca).
  c.listen(shiftDaysControllerProvider, (_, __) {});
  return c;
}

void main() {
  test('Ctrl+klik unaprijed izabere sve dane između sidra i cilja', () {
    final c = _container();
    addTearDown(c.dispose);
    final ctrl = _controller(c);

    ctrl.toggleDay('2026-08-04'); // sidro (običan klik)
    ctrl.selectRange('2026-08-08'); // Ctrl+klik

    final days = c.read(shiftDaysControllerProvider).selectedDays;
    expect(days, {
      '2026-08-04',
      '2026-08-05',
      '2026-08-06',
      '2026-08-07',
      '2026-08-08',
    });
  });

  test('Ctrl+klik unazad radi isto (cilj prije sidra)', () {
    final c = _container();
    addTearDown(c.dispose);
    final ctrl = _controller(c);

    ctrl.toggleDay('2026-08-10'); // sidro
    ctrl.selectRange('2026-08-08'); // unazad

    final days = c.read(shiftDaysControllerProvider).selectedDays;
    expect(days, {'2026-08-08', '2026-08-09', '2026-08-10'});
  });

  test('Ctrl+klik bez sidra se ponaša kao običan klik', () {
    final c = _container();
    addTearDown(c.dispose);
    final ctrl = _controller(c);

    ctrl.selectRange('2026-08-08'); // nema sidra → toggle

    final days = c.read(shiftDaysControllerProvider).selectedDays;
    expect(days, {'2026-08-08'});
  });

  test('Promjena mjeseca briše izbor i sidro', () {
    final c = _container();
    addTearDown(c.dispose);
    final ctrl = _controller(c);

    ctrl.toggleDay('2026-08-04');
    ctrl.shiftMonth(1);

    final state = c.read(shiftDaysControllerProvider);
    expect(state.selectedDays, isEmpty);
    expect(state.anchorDay, isNull);
  });
}
