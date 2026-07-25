import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/exceptions.dart';
import '../../models/models.dart';
import '../../services/providers.dart';
import '../../shared/format.dart';
import '../../shared/widgets.dart';
import 'product_badge.dart';
import 'product_detail_screen.dart';
import 'product_form.dart';
import 'products_provider.dart';

/// Ekran sa listom proizvoda: pretraga, filter po dobavljaču, paginacija,
/// bedž zalihe i „Niska zaliha“. Dodavanje/izmjena/brisanje samo za ADMIN.
class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
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
      ref.read(productsControllerProvider.notifier).loadMore();
    }
  }

  Future<void> _addProduct() async {
    final suppliers = await ref.read(suppliersProvider.future);
    if (!mounted) return;
    final request = await showProductForm(context, suppliers: suppliers);
    if (request == null) return;
    try {
      await ref.read(productsControllerProvider.notifier).create(request);
      if (mounted) showSnack(context, 'Proizvod sačuvan.');
    } catch (e) {
      if (mounted) showSnack(context, ApiException.from(e).message, isError: true);
    }
  }

  /// „Niska zaliha“ — donji panel sa proizvodima ispod praga (5).
  void _showLowStock() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => const _LowStockSheet(threshold: 5),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(productsControllerProvider);
    final isAdmin = ref.watch(authControllerProvider).isAdmin;

    return Scaffold(
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: _addProduct,
              icon: const Icon(Icons.add),
              label: const Text('Novi proizvod'),
            )
          : null,
      body: Column(
        children: [
          // Pretraga + dugme za nisku zalihu.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                Expanded(
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
                                    .read(productsControllerProvider.notifier)
                                    .setSearch('');
                                setState(() {});
                              },
                            ),
                    ),
                    onChanged: (v) {
                      ref
                          .read(productsControllerProvider.notifier)
                          .setSearch(v);
                      setState(() {});
                    },
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _showLowStock,
                  icon: const Icon(Icons.warning_amber_outlined),
                  label: const Text('Niska zaliha'),
                ),
              ],
            ),
          ),
          // Filter po dobavljaču.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: _SupplierFilter(
              selected: state.supplierId,
              onChanged: (id) =>
                  ref.read(productsControllerProvider.notifier).setSupplier(id),
            ),
          ),
          Expanded(child: _buildBody(state)),
        ],
      ),
    );
  }

  Widget _buildBody(ProductsState state) {
    if (state.isLoading) return const LoadingView();

    if (state.error != null && state.items.isEmpty) {
      return ErrorView(
        message: state.error!,
        onRetry: () =>
            ref.read(productsControllerProvider.notifier).loadFirstPage(),
      );
    }

    if (state.items.isEmpty) {
      return const EmptyView(
        message: 'Nema proizvoda.',
        icon: Icons.inventory_2_outlined,
      );
    }

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(productsControllerProvider.notifier).loadFirstPage(),
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
        itemCount: state.items.length + (state.hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index >= state.items.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: LoadingView(),
            );
          }
          final p = state.items[index];
          return Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.inventory_2)),
              title: Text(p.name ?? '—'),
              subtitle: Text(
                [
                  Format.money(p.finalPrice),
                  if (p.supplierName != null && p.supplierName!.isNotEmpty)
                    p.supplierName!,
                ].join('  ·  '),
              ),
              trailing: QuantityBadge(quantity: p.quantity),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProductDetailScreen(productId: p.id!),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Padajući filter po dobavljaču (uključuje opciju „Svi dobavljači“).
class _SupplierFilter extends ConsumerWidget {
  final int? selected;
  final ValueChanged<int?> onChanged;

  const _SupplierFilter({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suppliersAsync = ref.watch(suppliersProvider);
    return suppliersAsync.maybeWhen(
      data: (suppliers) => DropdownButtonFormField<int?>(
        value: selected,
        isDense: true,
        decoration: const InputDecoration(
          labelText: 'Dobavljač',
          prefixIcon: Icon(Icons.local_shipping_outlined),
          border: OutlineInputBorder(),
        ),
        items: [
          const DropdownMenuItem(value: null, child: Text('Svi dobavljači')),
          for (final s in suppliers)
            DropdownMenuItem(value: s.id, child: Text(s.name ?? 'Dobavljač ${s.id}')),
        ],
        onChanged: onChanged,
      ),
      orElse: () => const SizedBox.shrink(),
    );
  }
}

/// Donji panel sa proizvodima ispod praga zalihe.
class _LowStockSheet extends ConsumerWidget {
  final int threshold;

  const _LowStockSheet({required this.threshold});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(lowStockProvider(threshold));
    return SizedBox(
      height: 400,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Niska zaliha (≤ $threshold)',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          Expanded(
            child: AsyncValueView<List<LowStockItem>>(
              value: async,
              onRetry: () => ref.invalidate(lowStockProvider(threshold)),
              data: (items) {
                if (items.isEmpty) {
                  return const EmptyView(
                    message: 'Sve zalihe su iznad praga. 👍',
                    icon: Icons.check_circle_outline,
                  );
                }
                return ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final it = items[i];
                    return ListTile(
                      leading: const Icon(Icons.inventory_2_outlined),
                      title: Text(it.name ?? '—'),
                      subtitle:
                          Text(it.supplierName ?? 'Bez dobavljača'),
                      trailing: QuantityBadge(quantity: it.quantity),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
