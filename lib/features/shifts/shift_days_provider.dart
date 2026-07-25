import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/exceptions.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../services/providers.dart';
import 'shift_assignments_provider.dart' show ymd; // dijeli "YYYY-MM-DD" helper

/// Prvi/zadnji dan mjeseca kojem pripada dati datum.
DateTime _firstOfMonth(DateTime d) => DateTime(d.year, d.month, 1);
DateTime _lastOfMonth(DateTime d) => DateTime(d.year, d.month + 1, 0);

/// Stanje ekrana „Dodjela smjena" (mjesečni kalendar, dodjela po danu).
class ShiftDaysState {
  final DateTime month; // prvi dan prikazanog mjeseca
  final int? selectedEmployeeId; // aktivni (čekirani) barber
  final Set<String> selectedDays; // čekirani dani ("YYYY-MM-DD")
  final String? anchorDay; // sidro za Ctrl+klik izbor opsega (zadnji klik)
  final List<ShiftDayResponse> items; // smjene u mjesecu (svi barberi)
  final bool isLoading;
  final String? error; // greška pri učitavanju (npr. backend još nije spreman)

  const ShiftDaysState({
    required this.month,
    this.selectedEmployeeId,
    this.selectedDays = const {},
    this.anchorDay,
    this.items = const [],
    this.isLoading = false,
    this.error,
  });

  ShiftDaysState copyWith({
    DateTime? month,
    int? selectedEmployeeId,
    bool clearEmployee = false,
    Set<String>? selectedDays,
    String? anchorDay,
    bool clearAnchor = false,
    List<ShiftDayResponse>? items,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return ShiftDaysState(
      month: month ?? this.month,
      selectedEmployeeId:
          clearEmployee ? null : (selectedEmployeeId ?? this.selectedEmployeeId),
      selectedDays: selectedDays ?? this.selectedDays,
      anchorDay: clearAnchor ? null : (anchorDay ?? this.anchorDay),
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }

  /// Smjena datog barbera za dati dan ("YYYY-MM-DD"), ili `null` ako je slobodan.
  ShiftDayResponse? shiftFor(int employeeId, String day) {
    for (final s in items) {
      if (s.employeeId == employeeId && s.date == day) return s;
    }
    return null;
  }
}

/// Kontroler: bira mjesec/barbera/dane, učitava smjene, dodjeljuje i uklanja.
class ShiftDaysController extends StateNotifier<ShiftDaysState> {
  final ApiService _api;

  ShiftDaysController(this._api)
      : super(ShiftDaysState(month: _firstOfMonth(DateTime.now()))) {
    load();
  }

  /// Pomjeri prikaz za +/- mjeseci (čisti izbor dana).
  void shiftMonth(int months) {
    final m = DateTime(state.month.year, state.month.month + months, 1);
    state = state.copyWith(
        month: m, selectedDays: const {}, clearAnchor: true);
    load();
  }

  /// Postavi mjesec prema izabranom datumu.
  void setMonth(DateTime date) {
    state = state.copyWith(
        month: _firstOfMonth(date), selectedDays: const {}, clearAnchor: true);
    load();
  }

  /// Izaberi/poništi aktivnog barbera (ponovni klik na istog = poništi).
  /// Promjena barbera uvijek čisti izabrane dane.
  void selectEmployee(int? id) {
    final same = state.selectedEmployeeId == id;
    state = state.copyWith(
      selectedEmployeeId: same ? null : id,
      clearEmployee: same,
      selectedDays: const {},
      clearAnchor: true,
    );
  }

  /// Čekiraj/odčekiraj dan (običan klik). Postavlja sidro za izbor opsega.
  void toggleDay(String day) {
    final set = {...state.selectedDays};
    if (!set.add(day)) set.remove(day); // add vraća false ako već postoji
    state = state.copyWith(selectedDays: set, anchorDay: day);
  }

  /// Ctrl+klik: izaberi sve dane od sidra (zadnji klik) do [day] uključivo.
  /// Ako nema sidra, ponaša se kao običan klik.
  void selectRange(String day) {
    final anchor = state.anchorDay;
    if (anchor == null) {
      toggleDay(day);
      return;
    }
    final a = DateTime.parse(anchor);
    final b = DateTime.parse(day);
    final start = a.isAfter(b) ? b : a;
    final end = a.isAfter(b) ? a : b;
    final set = {...state.selectedDays};
    // Idemo dan po dan konstrukcijom datuma (bezbjedno oko ljetnjeg/zimskog vremena).
    for (var d = start; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) {
      set.add(ymd(d));
    }
    state = state.copyWith(selectedDays: set, anchorDay: day);
  }

  void clearDays() =>
      state = state.copyWith(selectedDays: const {}, clearAnchor: true);

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final list = await _api.getShiftDays(
        from: ymd(_firstOfMonth(state.month)),
        to: ymd(_lastOfMonth(state.month)),
      );
      if (!mounted) return; // ekran zatvoren u međuvremenu
      state = state.copyWith(items: list, isLoading: false);
    } catch (e) {
      if (!mounted) return;
      // Ne rušimo ekran — kalendar se i dalje prikazuje (prazan), uz poruku.
      state = state.copyWith(
        items: const [],
        isLoading: false,
        error: ApiException.from(e).message,
      );
    }
  }

  /// Grupna dodjela/izmjena smjene za izabrane dane (upsert po danu).
  /// Greške se propagiraju ekranu (koji prikaže poruku).
  Future<void> assign(List<ShiftDayRequest> requests) async {
    if (requests.isEmpty) return;
    await _api.putShiftDays(requests);
    await load();
    if (!mounted) return;
    state = state.copyWith(selectedDays: const {}, clearAnchor: true);
  }

  /// Ukloni smjenu za sve izabrane dane aktivnog barbera koji je imaju.
  Future<void> removeSelectedDays() async {
    final empId = state.selectedEmployeeId;
    if (empId == null) return;
    for (final day in state.selectedDays) {
      if (state.shiftFor(empId, day) != null) {
        await _api.deleteShiftDay(employeeId: empId, date: day);
      }
    }
    if (!mounted) return;
    await load();
    if (!mounted) return;
    state = state.copyWith(selectedDays: const {}, clearAnchor: true);
  }
}

final shiftDaysControllerProvider =
    StateNotifierProvider.autoDispose<ShiftDaysController, ShiftDaysState>(
        (ref) => ShiftDaysController(ref.watch(apiServiceProvider)));
