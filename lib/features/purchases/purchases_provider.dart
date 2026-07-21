import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/exceptions.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../services/providers.dart';

/// Stanje istorije nabavki: paginacija + filteri (dobavljač, period).
class PurchasesState {
  final List<PurchaseResponse> items;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;
  final int nextPage;
  final int? supplierId;
  final DateTimeRange? range;

  const PurchasesState({
    this.items = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
    this.nextPage = 0,
    this.supplierId,
    this.range,
  });

  PurchasesState copyWith({
    List<PurchaseResponse>? items,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    int? nextPage,
    int? supplierId,
    DateTimeRange? range,
    bool clearSupplier = false,
    bool clearRange = false,
  }) {
    return PurchasesState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: error,
      nextPage: nextPage ?? this.nextPage,
      supplierId: clearSupplier ? null : (supplierId ?? this.supplierId),
      range: clearRange ? null : (range ?? this.range),
    );
  }
}

class PurchasesController extends StateNotifier<PurchasesState> {
  final ApiService _api;

  PurchasesController(this._api) : super(const PurchasesState()) {
    loadFirstPage();
  }

  void setSupplier(int? supplierId) {
    state = state.copyWith(
      supplierId: supplierId,
      clearSupplier: supplierId == null,
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
    state = PurchasesState(
      isLoading: true,
      supplierId: state.supplierId,
      range: state.range,
    );
    try {
      final page = await _api.getPurchases(
        supplierId: state.supplierId,
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
      final page = await _api.getPurchases(
        supplierId: state.supplierId,
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

  /// Kreira nabavku i vraća je (za navigaciju na detalje). Zatim osvježi listu.
  Future<PurchaseResponse> create(PurchaseRequest request) async {
    final created = await _api.createPurchase(request);
    await loadFirstPage();
    return created;
  }
}

final purchasesControllerProvider =
    StateNotifierProvider<PurchasesController, PurchasesState>((ref) {
  return PurchasesController(ref.watch(apiServiceProvider));
});
