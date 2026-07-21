import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/exceptions.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../services/providers.dart';

// ------------------------- Pomoćne funkcije za sedmicu -------------------------

/// Ponedjeljak sedmice kojoj pripada dati datum (vrijeme se odbacuje).
DateTime mondayOf(DateTime d) {
  final date = DateTime(d.year, d.month, d.day);
  return date.subtract(Duration(days: date.weekday - 1)); // weekday: Pon=1
}

/// Datum u formatu koji server očekuje: "YYYY-MM-DD".
String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Svi šabloni smjena (za padajuću listu u formi dodjele).
///
/// Endpoint je paginiran, pa uzimamo prvu (veliku) stranicu — salon ima mali
/// broj šablona, tako da je ovo sasvim dovoljno.
final allShiftTemplatesProvider =
    FutureProvider<List<ShiftTemplateResponse>>((ref) async {
  final page = await ref
      .watch(apiServiceProvider)
      .getShiftTemplates(page: 0, size: 200, sort: 'name,asc');
  return page.content;
});

/// Stanje ekrana dodjele smjena: izabrana sedmica + dodjele te sedmice.
class ShiftAssignmentsState {
  final DateTime weekStart; // ponedjeljak izabrane sedmice
  final List<ShiftAssignmentResponse> items;
  final bool isLoading;
  final String? error;

  const ShiftAssignmentsState({
    required this.weekStart,
    this.items = const [],
    this.isLoading = false,
    this.error,
  });

  ShiftAssignmentsState copyWith({
    DateTime? weekStart,
    List<ShiftAssignmentResponse>? items,
    bool? isLoading,
    String? error, // namjerno bez `?? this.error` (novo učitavanje briše grešku)
  }) {
    return ShiftAssignmentsState(
      weekStart: weekStart ?? this.weekStart,
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// Kontroler dodjela smjena: bira sedmicu, učitava dodjele, CRUD.
class ShiftAssignmentsController
    extends StateNotifier<ShiftAssignmentsState> {
  final ApiService _api;

  ShiftAssignmentsController(this._api)
      : super(ShiftAssignmentsState(weekStart: mondayOf(DateTime.now()))) {
    load();
  }

  /// Pomjeri prikaz za +/- sedmica.
  void shiftWeek(int weeks) {
    state = state.copyWith(
        weekStart: state.weekStart.add(Duration(days: 7 * weeks)));
    load();
  }

  /// Postavi sedmicu prema izabranom datumu (uzima se njegov ponedjeljak).
  void setWeekFromDate(DateTime date) {
    state = state.copyWith(weekStart: mondayOf(date));
    load();
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true);
    try {
      // Dodjele su ključane po ponedjeljku, pa je dovoljno from=to=ponedjeljak.
      final day = ymd(state.weekStart);
      final list = await _api.getShiftAssignments(from: day, to: day);
      state = state.copyWith(items: list, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: ApiException.from(e).message,
      );
    }
  }

  // CRUD — greške se hvataju na ekranu (koji prikaže poruku).
  Future<void> create(ShiftAssignmentRequest request) async {
    await _api.createShiftAssignment(request);
    await load();
  }

  Future<void> update(int id, ShiftAssignmentRequest request) async {
    await _api.updateShiftAssignment(id, request);
    await load();
  }

  Future<void> delete(int id) async {
    await _api.deleteShiftAssignment(id);
    await load();
  }
}

final shiftAssignmentsControllerProvider =
    StateNotifierProvider<ShiftAssignmentsController, ShiftAssignmentsState>(
        (ref) {
  return ShiftAssignmentsController(ref.watch(apiServiceProvider));
});
