import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/exceptions.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../services/providers.dart';

/// Lista dobavljača za padajuće liste/filtere (povučemo prvu veliku stranicu).
final suppliersProvider = FutureProvider<List<SupplierResponse>>((ref) async {
  final page = await ref.watch(apiServiceProvider).getSuppliers(
        page: 0,
        size: 200,
        sort: 'name,asc',
      );
  return page.content;
});

/// Proizvodi sa malom zalihom (za „Niska zaliha“ tabelu).
final lowStockProvider =
    FutureProvider.autoDispose.family<List<LowStockItem>, int>((ref, threshold) {
  return ref.watch(apiServiceProvider).getLowStock(threshold: threshold);
});

/// Pretraga proizvoda po nazivu (za biranje proizvoda u nabavkama/prodajama).
final productSearchProvider =
    FutureProvider.autoDispose.family<List<ProductResponse>, String>(
        (ref, query) async {
  final page = await ref.watch(apiServiceProvider).getProducts(
        name: query.trim().isEmpty ? null : query.trim(),
        page: 0,
        size: 30,
        sort: 'name,asc',
      );
  return page.content;
});

/// Stanje liste proizvoda: paginacija + pretraga + filter po dobavljaču.
class ProductsState {
  final List<ProductResponse> items;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;
  final int nextPage;
  final String query;
  final int? supplierId; // filter po dobavljaču (null = svi)

  const ProductsState({
    this.items = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
    this.nextPage = 0,
    this.query = '',
    this.supplierId,
  });

  ProductsState copyWith({
    List<ProductResponse>? items,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    int? nextPage,
    String? query,
    int? supplierId,
    bool clearSupplier = false,
  }) {
    return ProductsState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: error,
      nextPage: nextPage ?? this.nextPage,
      query: query ?? this.query,
      supplierId: clearSupplier ? null : (supplierId ?? this.supplierId),
    );
  }
}

/// Kontroler za proizvode: paginacija, pretraga, filter, CRUD.
class ProductsController extends StateNotifier<ProductsState> {
  final ApiService _api;
  Timer? _debounce;

  ProductsController(this._api) : super(const ProductsState()) {
    loadFirstPage();
  }

  void setSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (value == state.query) return;
      state = state.copyWith(query: value);
      loadFirstPage();
    });
  }

  void setSupplier(int? supplierId) {
    state = state.copyWith(
      supplierId: supplierId,
      clearSupplier: supplierId == null,
    );
    loadFirstPage();
  }

  Future<void> loadFirstPage() async {
    state = ProductsState(
      isLoading: true,
      query: state.query,
      supplierId: state.supplierId,
    );
    try {
      final page = await _api.getProducts(
        name: state.query.trim().isEmpty ? null : state.query.trim(),
        supplierId: state.supplierId,
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
      final page = await _api.getProducts(
        name: state.query.trim().isEmpty ? null : state.query.trim(),
        supplierId: state.supplierId,
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

  Future<void> create(ProductRequest request) async {
    await _api.createProduct(request);
    await loadFirstPage();
  }

  Future<void> update(int id, ProductRequest request) async {
    await _api.updateProduct(id, request);
    await loadFirstPage();
  }

  Future<void> delete(int id) async {
    await _api.deleteProduct(id);
    await loadFirstPage();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

final productsControllerProvider =
    StateNotifierProvider<ProductsController, ProductsState>((ref) {
  return ProductsController(ref.watch(apiServiceProvider));
});
