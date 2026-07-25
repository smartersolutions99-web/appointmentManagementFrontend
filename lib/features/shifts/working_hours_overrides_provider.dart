import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/exceptions.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../services/providers.dart';
import 'shift_assignments_provider.dart' show ymd; // dijeli "YYYY-MM-DD" helper

DateTime _firstOfMonth(DateTime d) => DateTime(d.year, d.month, 1);
DateTime _lastOfMonth(DateTime d) => DateTime(d.year, d.month + 1, 0);

/// Stanje kalendara radnog vremena (izuzeci po datumu preko sedmičnog šablona).
class WorkingHoursCalendarState {
  final DateTime month; // prvi dan prikazanog mjeseca
  final Set<String> selectedDays; // čekirani dani ("YYYY-MM-DD")
  final String? anchorDay; // sidro za Ctrl+klik izbor opsega
  final Map<WeekDay, WorkingHoursResponse> weekly; // sedmični default po danu
  final Map<String, WorkingHoursOverrideResponse> overrides; // izuzeci po datumu
  final bool isLoading;
  final String? error; // greška za IZUZETKE (npr. backend još nije spreman)

  const WorkingHoursCalendarState({
    required this.month,
    this.selectedDays = const {},
    this.anchorDay,
    this.weekly = const {},
    this.overrides = const {},
    this.isLoading = false,
    this.error,
  });

  WorkingHoursCalendarState copyWith({
    DateTime? month,
    Set<String>? selectedDays,
    String? anchorDay,
    bool clearAnchor = false,
    Map<WeekDay, WorkingHoursResponse>? weekly,
    Map<String, WorkingHoursOverrideResponse>? overrides,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return WorkingHoursCalendarState(
      month: month ?? this.month,
      selectedDays: selectedDays ?? this.selectedDays,
      anchorDay: clearAnchor ? null : (anchorDay ?? this.anchorDay),
      weekly: weekly ?? this.weekly,
      overrides: overrides ?? this.overrides,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }

  /// Izuzetak za dati dan ("YYYY-MM-DD"), ili `null`.
  WorkingHoursOverrideResponse? overrideForDay(String day) => overrides[day];

  /// Sedmični default za dati datum (null = tog dana u sedmici salon ne radi).
  WorkingHoursResponse? weeklyForDate(DateTime date) =>
      weekly[WeekDay.values[date.weekday - 1]];
}

/// Kontroler: bira mjesec/dane, učitava sedmični default + izuzetke, upisuje/briše.
class WorkingHoursCalendarController
    extends StateNotifier<WorkingHoursCalendarState> {
  final ApiService _api;

  WorkingHoursCalendarController(this._api)
      : super(WorkingHoursCalendarState(month: _firstOfMonth(DateTime.now()))) {
    load();
  }

  void shiftMonth(int months) {
    final m = DateTime(state.month.year, state.month.month + months, 1);
    state =
        state.copyWith(month: m, selectedDays: const {}, clearAnchor: true);
    load();
  }

  void setMonth(DateTime date) {
    state = state.copyWith(
        month: _firstOfMonth(date), selectedDays: const {}, clearAnchor: true);
    load();
  }

  /// Običan klik: čekiraj/odčekiraj dan (postavlja sidro za opseg).
  void toggleDay(String day) {
    final set = {...state.selectedDays};
    if (!set.add(day)) set.remove(day);
    state = state.copyWith(selectedDays: set, anchorDay: day);
  }

  /// Ctrl+klik: izaberi sve dane od sidra do [day] uključivo.
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
    for (var d = start;
        !d.isAfter(end);
        d = DateTime(d.year, d.month, d.day + 1)) {
      set.add(ymd(d));
    }
    state = state.copyWith(selectedDays: set, anchorDay: day);
  }

  void clearDays() =>
      state = state.copyWith(selectedDays: const {}, clearAnchor: true);

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);

    // Sedmični default (best-effort — ako padne, samo nemamo default prikaz).
    var weekly = <WeekDay, WorkingHoursResponse>{};
    try {
      final list = await _api.getWorkingHours();
      weekly = {for (final w in list) w.dayOfWeek: w};
    } catch (_) {
      // ignorišemo — kalendar i dalje radi, samo bez default sati
    }
    if (!mounted) return;

    // Izuzeci po datumu (može pasti ako backend još nije spreman).
    try {
      final ov = await _api.getWorkingHoursOverrides(
        from: ymd(_firstOfMonth(state.month)),
        to: ymd(_lastOfMonth(state.month)),
      );
      if (!mounted) return;
      state = state.copyWith(
        weekly: weekly,
        overrides: {for (final o in ov) if (o.date != null) o.date!: o},
        isLoading: false,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        weekly: weekly,
        overrides: const {},
        isLoading: false,
        error: ApiException.from(e).message,
      );
    }
  }

  /// Označi izabrane dane kao NERADNE (zatvoreno).
  Future<void> markClosed(Iterable<String> days) async {
    final reqs = [
      for (final d in days) WorkingHoursOverrideRequest(date: d, closed: true),
    ];
    if (reqs.isEmpty) return;
    await _api.putWorkingHoursOverrides(reqs);
    await _reloadAndClear();
  }

  /// Postavi radno vrijeme (opensAt/closesAt "HH:mm:ss") za izabrane dane.
  Future<void> setHours(
      Iterable<String> days, String opensAt, String closesAt) async {
    final reqs = [
      for (final d in days)
        WorkingHoursOverrideRequest(
          date: d,
          closed: false,
          opensAt: opensAt,
          closesAt: closesAt,
        ),
    ];
    if (reqs.isEmpty) return;
    await _api.putWorkingHoursOverrides(reqs);
    await _reloadAndClear();
  }

  /// Ukloni izuzetke za izabrane dane → vraćaju se na sedmični šablon.
  Future<void> revert(Iterable<String> days) async {
    for (final d in days) {
      if (state.overrides.containsKey(d)) {
        await _api.deleteWorkingHoursOverride(d);
      }
    }
    await _reloadAndClear();
  }

  Future<void> _reloadAndClear() async {
    if (!mounted) return;
    await load();
    if (!mounted) return;
    state = state.copyWith(selectedDays: const {}, clearAnchor: true);
  }
}

final workingHoursCalendarProvider = StateNotifierProvider.autoDispose<
    WorkingHoursCalendarController, WorkingHoursCalendarState>(
  (ref) => WorkingHoursCalendarController(ref.watch(apiServiceProvider)),
);
