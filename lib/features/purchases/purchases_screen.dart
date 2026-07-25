import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/format.dart';
import '../../shared/widgets.dart';
import '../products/products_provider.dart';
import 'new_purchase_screen.dart';
import 'purchase_detail_screen.dart';
import 'purchases_provider.dart';

/// Istorija nabavki: paginirana lista sa filterima (dobavljač + period).
/// „Nova nabavka“ je dostupna oba role. Tap na red otvara detalje.
class PurchasesScreen extends ConsumerStatefulWidget {
  const PurchasesScreen({super.key});

  @override
  ConsumerState<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends ConsumerState<PurchasesScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final p = _scrollController.position;
    if (p.pixels >= p.maxScrollExtent - 200) {
      ref.read(purchasesControllerProvider.notifier).loadMore();
    }
  }

  Future<void> _pickRange() async {
    final current = ref.read(purchasesControllerProvider).range;
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: current,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      ref.read(purchasesControllerProvider.notifier).setRange(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(purchasesControllerProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NewPurchaseScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Nova nabavka'),
      ),
      body: Column(
        children: [
          _buildFilters(state),
          Expanded(child: _buildBody(state)),
        ],
      ),
    );
  }

  Widget _buildFilters(PurchasesState state) {
    final suppliersAsync = ref.watch(suppliersProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: suppliersAsync.maybeWhen(
              data: (suppliers) => DropdownButtonFormField<int?>(
                value: state.supplierId,
                isDense: true,
                decoration: const InputDecoration(
                  labelText: 'Dobavljač',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text('Svi dobavljači')),
                  for (final s in suppliers)
                    DropdownMenuItem(
                        value: s.id,
                        child: Text(s.name ?? 'Dobavljač ${s.id}')),
                ],
                onChanged: (v) => ref
                    .read(purchasesControllerProvider.notifier)
                    .setSupplier(v),
              ),
              orElse: () => const SizedBox.shrink(),
            ),
          ),
          const SizedBox(width: 8),
          // Period.
          OutlinedButton.icon(
            onPressed: _pickRange,
            icon: const Icon(Icons.date_range),
            label: Text(state.range == null
                ? 'Period'
                : '${Format.date(state.range!.start)}–${Format.date(state.range!.end)}'),
          ),
          if (state.range != null)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'Poništi period',
              onPressed: () =>
                  ref.read(purchasesControllerProvider.notifier).setRange(null),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(PurchasesState state) {
    if (state.isLoading) return const LoadingView();

    if (state.error != null && state.items.isEmpty) {
      return ErrorView(
        message: state.error!,
        onRetry: () =>
            ref.read(purchasesControllerProvider.notifier).loadFirstPage(),
      );
    }

    if (state.items.isEmpty) {
      return const EmptyView(
        message: 'Nema nabavki.',
        icon: Icons.inventory_outlined,
      );
    }

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(purchasesControllerProvider.notifier).loadFirstPage(),
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
              leading: const CircleAvatar(child: Icon(Icons.inventory)),
              title: Text(p.supplierName ?? 'Bez dobavljača'),
              subtitle: Text(
                '${Format.dateTime(p.createdAt)}  ·  ${p.items.length} stavki',
              ),
              trailing: Text(
                Format.money(p.totalCost),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PurchaseDetailScreen(purchaseId: p.id!),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
