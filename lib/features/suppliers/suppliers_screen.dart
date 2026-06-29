import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/exceptions.dart';
import '../../models/models.dart';
import '../../services/providers.dart';
import '../../shared/widgets.dart';
import 'supplier_detail_screen.dart';
import 'supplier_form.dart';
import 'suppliers_provider.dart';

/// Ekran sa listom dobavljača: pretraga, paginacija (beskonačni skrol),
/// dodavanje (ADMIN). Tap na red otvara detalje.
class SuppliersScreen extends ConsumerStatefulWidget {
  const SuppliersScreen({super.key});

  @override
  ConsumerState<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends ConsumerState<SuppliersScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final p = _scrollController.position;
    if (p.pixels >= p.maxScrollExtent - 200) {
      ref.read(suppliersControllerProvider.notifier).loadMore();
    }
  }

  /// Dodavanje novog dobavljača (samo ADMIN).
  Future<void> _addSupplier() async {
    final request = await showSupplierForm(context);
    if (request == null) return;
    try {
      await ref.read(suppliersControllerProvider.notifier).create(request);
      if (mounted) showSnack(context, 'Dobavljač sačuvan.');
    } catch (e) {
      if (mounted) showSnack(context, ApiException.from(e).message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(suppliersControllerProvider);
    final isAdmin = ref.watch(authControllerProvider).isAdmin;

    return Scaffold(
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: _addSupplier,
              icon: const Icon(Icons.add),
              label: const Text('Novi dobavljač'),
            )
          : null,
      body: Column(
        children: [
          // Pretraga (debounce je u kontroleru).
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Pretraga po nazivu…',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          ref
                              .read(suppliersControllerProvider.notifier)
                              .setSearch('');
                          setState(() {});
                        },
                      ),
              ),
              onChanged: (v) {
                ref.read(suppliersControllerProvider.notifier).setSearch(v);
                setState(() {}); // da se osvježi „clear“ ikonica
              },
            ),
          ),
          Expanded(child: _buildBody(state)),
        ],
      ),
    );
  }

  Widget _buildBody(SuppliersState state) {
    if (state.isLoading) return const LoadingView();

    if (state.error != null && state.items.isEmpty) {
      return ErrorView(
        message: state.error!,
        onRetry: () =>
            ref.read(suppliersControllerProvider.notifier).loadFirstPage(),
      );
    }

    if (state.items.isEmpty) {
      return const EmptyView(
        message: 'Nema dobavljača.',
        icon: Icons.local_shipping_outlined,
      );
    }

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(suppliersControllerProvider.notifier).loadFirstPage(),
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
        itemCount: state.items.length + (state.hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index >= state.items.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final supplier = state.items[index];
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                child: Text(
                  (supplier.name?.isNotEmpty ?? false)
                      ? supplier.name![0].toUpperCase()
                      : '?',
                ),
              ),
              title: Text(supplier.name ?? 'Bez naziva'),
              subtitle: Text(supplier.contactValue ?? '—'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openDetail(supplier),
            ),
          );
        },
      ),
    );
  }

  void _openDetail(SupplierResponse supplier) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SupplierDetailScreen(supplierId: supplier.id!),
      ),
    );
  }
}
