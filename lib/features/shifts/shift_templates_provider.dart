import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/exceptions.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../services/providers.dart';
import 'shift_assignments_provider.dart' show allShiftTemplatesProvider;

/// Stanje liste šablona smjena: paginacija (beskonačni skrol) + pretraga.
/// (Isti obrazac kao kod dobavljača/proizvoda.)
class ShiftTemplatesState {
  final List<ShiftTemplateResponse> items;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;
  final int nextPage;
  final String query; // tekuća pretraga (po nazivu)

  const ShiftTemplatesState({
    this.items = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
    this.nextPage = 0,
    this.query = '',
  });

  ShiftTemplatesState copyWith({
    List<ShiftTemplateResponse>? items,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    int? nextPage,
    String? query,
  }) {
    return ShiftTemplatesState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: error, // namjerno bez `?? this.error` da možemo obrisati grešku
      nextPage: nextPage ?? this.nextPage,
      query: query ?? this.query,
    );
  }
}

/// Kontroler za šablone smjena: učitavanje po stranicama, pretraga, CRUD.
class ShiftTemplatesController extends StateNotifier<ShiftTemplatesState> {
  final ApiService _api;
  final Ref _ref; // za osvježavanje liste šablona u formi dodjele smjene
  Timer? _debounce;

  ShiftTemplatesController(this._api, this._ref)
      : super(const ShiftTemplatesState()) {
    loadFirstPage();
  }

  /// Pretraga sa „debounce“-om (~300 ms) — ne zovemo API na svaki pritisak.
  void setSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (value == state.query) return;
      state = state.copyWith(query: value);
      loadFirstPage();
    });
  }

  Future<void> loadFirstPage() async {
    state = ShiftTemplatesState(isLoading: true, query: state.query);
    try {
      final page = await _api.getShiftTemplates(
        name: state.query.trim().isEmpty ? null : state.query.trim(),
        page: 0,
        size: AppConfig.defaultPageSize,
        sort: 'name,asc',
      );
      state = state.copyWith(
        items: page.content,
        isLoading: false,
        hasMore: !page.last,
        nextPage: 1,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: ApiException.from(e).message,
      );
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore || state.isLoading) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final page = await _api.getShiftTemplates(
        name: state.query.trim().isEmpty ? null : state.query.trim(),
        page: state.nextPage,
        size: AppConfig.defaultPageSize,
        sort: 'name,asc',
      );
      state = state.copyWith(
        items: [...state.items, ...page.content],
        isLoadingMore: false,
        hasMore: !page.last,
        nextPage: state.nextPage + 1,
      );
    } catch (e) {
      state = state.copyWith(
        isLoadingMore: false,
        error: ApiException.from(e).message,
      );
    }
  }

  // CRUD — greške se namjerno NE hvataju ovdje, nego u formi (koja prikaže poruku).
  // Nakon svake izmjene osvježavamo i `allShiftTemplatesProvider` (padajuća lista
  // šablona u formi dodjele smjene), da tamo ne ostane stara vrijednost.
  Future<void> create(ShiftTemplateRequest request) async {
    await _api.createShiftTemplate(request);
    _ref.invalidate(allShiftTemplatesProvider);
    await loadFirstPage();
  }

  Future<void> update(int id, ShiftTemplateRequest request) async {
    await _api.updateShiftTemplate(id, request);
    _ref.invalidate(allShiftTemplatesProvider);
    await loadFirstPage();
  }

  Future<void> delete(int id) async {
    await _api.deleteShiftTemplate(id);
    _ref.invalidate(allShiftTemplatesProvider);
    await loadFirstPage();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

final shiftTemplatesControllerProvider =
    StateNotifierProvider<ShiftTemplatesController, ShiftTemplatesState>((ref) {
  return ShiftTemplatesController(ref.watch(apiServiceProvider), ref);
});
