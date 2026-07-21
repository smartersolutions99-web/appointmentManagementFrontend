import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/exceptions.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../services/providers.dart';

/// Stanje istorije prodaja: paginacija + filteri (zaposleni, interno da/ne, period).
///
/// NAPOMENA o `employeeId`: filter po zaposlenom smije koristiti SAMO admin.
/// Zaposleni vidi automatski samo svoje prodaje (server to izvlači iz tokena),
/// pa mu ovaj filter uopšte ne prikazujemo i ne šaljemo `employeeId`.
class SalesState {
  final List<SaleResponse> items;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;
  final int nextPage;
  final int? employeeId; // filter po zaposlenom (samo admin; null = svi)
  final bool? isInternal; // null = sve, true = samo interne, false = samo prodaje
  final DateTimeRange? range;

  const SalesState({
    this.items = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
    this.nextPage = 0,
    this.employeeId,
    this.isInternal,
    this.range,
  });

  SalesState copyWith({
    List<SaleResponse>? items,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    int? nextPage,
    int? employeeId,
    bool? isInternal,
    DateTimeRange? range,
    bool clearEmployee = false,
    bool clearInternal = false,
    bool clearRange = false,
  }) {
    return SalesState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: error,
      nextPage: nextPage ?? this.nextPage,
      employeeId: clearEmployee ? null : (employeeId ?? this.employeeId),
      isInternal: clearInternal ? null : (isInternal ?? this.isInternal),
      range: clearRange ? null : (range ?? this.range),
    );
  }
}

class SalesController extends StateNotifier<SalesState> {
  final ApiService _api;

  SalesController(this._api) : super(const SalesState()) {
    loadFirstPage();
  }

  void setEmployee(int? employeeId) {
    state = state.copyWith(
      employeeId: employeeId,
      clearEmployee: employeeId == null,
    );
    loadFirstPage();
  }

  void setInternal(bool? isInternal) {
    state = state.copyWith(
      isInternal: isInternal,
      clearInternal: isInternal == null,
    );
    loadFirstPage();
  }

  void setRange(DateTimeRange? range) {
    state = state.copyWith(range: range, clearRange: range == null);
    loadFirstPage();
  }

  String? get _from => state.range?.start.toUtc().toIso8601String();
  // Uključujemo cijeli krajnji dan (+1 dan).
  String? get _to => state.range?.end
      .add(const Duration(days: 1))
      .toUtc()
      .toIso8601String();

  Future<void> loadFirstPage() async {
    state = SalesState(
      isLoading: true,
      employeeId: state.employeeId,
      isInternal: state.isInternal,
      range: state.range,
    );
    try {
      final page = await _api.getSales(
        employeeId: state.employeeId,
        isInternal: state.isInternal,
        from: _from,
        to: _to,
        page: 0,
        size: AppConfig.defaultPageSize,
        sort: 'createdAt,desc',
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
      final page = await _api.getSales(
        employeeId: state.employeeId,
        isInternal: state.isInternal,
        from: _from,
        to: _to,
        page: state.nextPage,
        size: AppConfig.defaultPageSize,
        sort: 'createdAt,desc',
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

  /// Kreira prodaju i vraća je (za navigaciju na detalje). Zatim osvježi listu.
  Future<SaleResponse> create(SaleRequest request) async {
    final created = await _api.createSale(request);
    await loadFirstPage();
    return created;
  }
}

final salesControllerProvider =
    StateNotifierProvider<SalesController, SalesState>((ref) {
  return SalesController(ref.watch(apiServiceProvider));
});
