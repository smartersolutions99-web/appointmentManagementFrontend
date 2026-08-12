import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/exceptions.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../services/providers.dart';

/// Stanje liste klijenata sa paginacijom.
///
/// „Immutable“ klasa: ne mijenjamo je direktno, već pravimo novu kopiju
/// pomoću `copyWith`. Tako Riverpod pouzdano zna kada se nešto promijenilo.
class CustomersState {
  final List<CustomerResponse> items; // učitani klijenti (sve stranice zajedno)
  final bool isLoading; // prvo učitavanje
  final bool isLoadingMore; // dohvatanje sljedeće stranice
  final bool hasMore; // ima li još stranica
  final String? error; // poruka greške (ako postoji)
  final int nextPage; // koja stranica se sljedeća učitava

  const CustomersState({
    this.items = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
    this.nextPage = 0,
  });

  CustomersState copyWith({
    List<CustomerResponse>? items,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    int? nextPage,
  }) {
    return CustomersState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: error, // namjerno bez `?? this.error` da možemo obrisati grešku
      nextPage: nextPage ?? this.nextPage,
    );
  }
}

/// Kontroler koji učitava klijente stranicu po stranicu i obavlja CRUD radnje.
class CustomersController extends StateNotifier<CustomersState> {
  final ApiService _api;

  CustomersController(this._api) : super(const CustomersState()) {
    loadFirstPage(); // Odmah učitaj prvu stranicu kad se kontroler napravi.
  }

  /// Učitava prvu stranicu (resetuje listu). Koristi se i za „povuci da osvježiš“.
  Future<void> loadFirstPage() async {
    state = const CustomersState(isLoading: true);
    try {
      final page = await _api.getCustomers(
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

  /// Učitava sljedeću stranicu i dodaje je na postojeću listu (beskonačni skrol).
  Future<void> loadMore() async {
    // Ne učitavaj ako već učitavamo ili nema više podataka.
    if (state.isLoadingMore || !state.hasMore || state.isLoading) return;

    state = state.copyWith(isLoadingMore: true);
    try {
      final page = await _api.getCustomers(
        page: state.nextPage,
        size: AppConfig.defaultPageSize,
        sort: 'name,asc',
      );
      state = state.copyWith(
        items: [...state.items, ...page.content], // spoji stare i nove
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

  /// Kreira novog klijenta, pa osvježava listu.
  Future<void> create(CustomerRequest request) async {
    await _api.createCustomer(request);
    await loadFirstPage();
  }

  /// Mijenja postojećeg klijenta, pa osvježava listu.
  Future<void> update(int id, CustomerRequest request) async {
    await _api.updateCustomer(id, request);
    await loadFirstPage();
  }

  /// Briše klijenta, pa osvježava listu.
  Future<void> delete(int id) async {
    await _api.deleteCustomer(id);
    await loadFirstPage();
  }
}

/// Provider preko kojeg ekran dolazi do kontrolera i stanja.
final customersControllerProvider =
    StateNotifierProvider<CustomersController, CustomersState>((ref) {
  return CustomersController(ref.watch(apiServiceProvider));
});

/// Statistika jednog klijenta (po id-u) — za detalj klijenta (potrošeno, brojevi
/// po statusu, alert za česte no-show).
final customerStatsProvider = FutureProvider.autoDispose
    .family<CustomerStatsResponse, int>((ref, id) {
  return ref.watch(apiServiceProvider).getCustomerStats(id);
});

/// Prag za upozorenje „čest no-show" na detalju klijenta.
const int kFrequentNoShowThreshold = 3;
