import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/exceptions.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../services/providers.dart';

/// Stanje liste dobavljača: paginacija (beskonačni skrol) + pretraga.
class SuppliersState {
  final List<SupplierResponse> items;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;
  final int nextPage;
  final String query; // tekuća pretraga (po imenu)

  const SuppliersState({
    this.items = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
    this.nextPage = 0,
    this.query = '',
  });

  SuppliersState copyWith({
    List<SupplierResponse>? items,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    int? nextPage,
    String? query,
  }) {
    return SuppliersState(
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

/// Kontroler za dobavljače: učitavanje po stranicama, pretraga, CRUD.
class SuppliersController extends StateNotifier<SuppliersState> {
  final ApiService _api;
  Timer? _debounce;

  SuppliersController(this._api) : super(const SuppliersState()) {
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
    state = SuppliersState(isLoading: true, query: state.query);
    try {
      final page = await _api.getSuppliers(
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
      final page = await _api.getSuppliers(
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

  Future<void> create(SupplierRequest request) async {
    await _api.createSupplier(request);
    await loadFirstPage();
  }

  Future<void> update(int id, SupplierRequest request) async {
    await _api.updateSupplier(id, request);
    await loadFirstPage();
  }

  Future<void> delete(int id) async {
    await _api.deleteSupplier(id);
    await loadFirstPage();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

final suppliersControllerProvider =
    StateNotifierProvider<SuppliersController, SuppliersState>((ref) {
  return SuppliersController(ref.watch(apiServiceProvider));
});
