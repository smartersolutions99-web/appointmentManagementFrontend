import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/exceptions.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../services/providers.dart';

/// Stanje liste termina sa paginacijom i filterom po statusu.
class AppointmentsState {
  final List<AppointmentResponse> items;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;
  final int nextPage;
  final AppointmentStatus? statusFilter; // null = svi statusi

  const AppointmentsState({
    this.items = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
    this.nextPage = 0,
    this.statusFilter,
  });

  AppointmentsState copyWith({
    List<AppointmentResponse>? items,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    int? nextPage,
    AppointmentStatus? statusFilter,
    bool clearStatusFilter = false,
  }) {
    return AppointmentsState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: error,
      nextPage: nextPage ?? this.nextPage,
      // Dozvoljavamo da eksplicitno obrišemo filter (postavimo na null).
      statusFilter: clearStatusFilter ? null : (statusFilter ?? this.statusFilter),
    );
  }
}

/// Kontroler za termine: paginacija, filter, kreiranje, promjena statusa, brisanje.
class AppointmentsController extends StateNotifier<AppointmentsState> {
  final ApiService _api;

  AppointmentsController(this._api) : super(const AppointmentsState()) {
    loadFirstPage();
  }

  Future<void> loadFirstPage() async {
    // Zadrži trenutni filter pri osvježavanju.
    final filter = state.statusFilter;
    state = AppointmentsState(isLoading: true, statusFilter: filter);
    try {
      final page = await _api.getAppointments(
        status: filter?.apiValue,
        page: 0,
        size: AppConfig.defaultPageSize,
        sort: 'startTime,desc',
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
      final page = await _api.getAppointments(
        status: state.statusFilter?.apiValue,
        page: state.nextPage,
        size: AppConfig.defaultPageSize,
        sort: 'startTime,desc',
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

  /// Postavlja filter po statusu (ili ga uklanja ako je `null`) i osvježava.
  Future<void> setStatusFilter(AppointmentStatus? status) async {
    state = state.copyWith(
      statusFilter: status,
      clearStatusFilter: status == null,
    );
    await loadFirstPage();
  }

  Future<void> create(AppointmentRequest request) async {
    await _api.createAppointment(request);
    await loadFirstPage();
  }

  Future<void> changeStatus(int id, AppointmentStatus status) async {
    await _api.changeAppointmentStatus(id, StatusChangeRequest(status: status));
    await loadFirstPage();
  }

  Future<void> delete(int id) async {
    await _api.deleteAppointment(id);
    await loadFirstPage();
  }
}

final appointmentsControllerProvider =
    StateNotifierProvider<AppointmentsController, AppointmentsState>((ref) {
  return AppointmentsController(ref.watch(apiServiceProvider));
});
