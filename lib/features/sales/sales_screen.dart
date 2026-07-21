import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/providers.dart';
import '../../shared/format.dart';
import '../../shared/widgets.dart';
import '../employees/employees_provider.dart';
import 'new_sale_screen.dart';
import 'sale_detail_screen.dart';
import 'sales_provider.dart';

/// Istorija prodaja: paginirana lista sa filterima.
/// „Nova prodaja“ je dostupna oba role. Zaposleni vidi samo svoje prodaje;
/// filter po zaposlenom prikazujemo samo administratoru. Tap na red → detalji.
class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({super.key});

  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen> {
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
      ref.read(salesControllerProvider.notifier).loadMore();
    }
  }

  Future<void> _pickRange() async {
    final current = ref.read(salesControllerProvider).range;
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: current,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      ref.read(salesControllerProvider.notifier).setRange(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(salesControllerProvider);
    final isAdmin = ref.watch(authControllerProvider).isAdmin;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NewSaleScreen()),
        ),
        icon: const Icon(Icons.point_of_sale),
        label: const Text('Nova prodaja'),
      ),
      body: Column(
        children: [
          _buildFilters(state, isAdmin),
          Expanded(child: _buildBody(state)),
        ],
      ),
    );
  }

  Widget _buildFilters(SalesState state, bool isAdmin) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Filter po zaposlenom — samo administrator.
          if (isAdmin) _buildEmployeeFilter(state),
          // Filter: interno / prodaja / sve.
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<bool?>(
              value: state.isInternal,
              isDense: true,
              decoration: const InputDecoration(
                labelText: 'Vrsta',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: null, child: Text('Sve')),
                DropdownMenuItem(value: false, child: Text('Prodaje')),
                DropdownMenuItem(value: true, child: Text('Interno (barber)')),
              ],
              onChanged: (v) =>
                  ref.read(salesControllerProvider.notifier).setInternal(v),
            ),
          ),
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
                  ref.read(salesControllerProvider.notifier).setRange(null),
            ),
        ],
      ),
    );
  }

  Widget _buildEmployeeFilter(SalesState state) {
    final employeesAsync = ref.watch(employeesProvider);
    return SizedBox(
      width: 220,
      child: employeesAsync.maybeWhen(
        data: (employees) => DropdownButtonFormField<int?>(
          value: state.employeeId,
          isDense: true,
          decoration: const InputDecoration(
            labelText: 'Zaposleni',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem(value: null, child: Text('Svi zaposleni')),
            for (final e in employees)
              DropdownMenuItem(
                value: e.id,
                child: Text(e.name ?? 'Zaposleni ${e.id}'),
              ),
          ],
          onChanged: (v) =>
              ref.read(salesControllerProvider.notifier).setEmployee(v),
        ),
        orElse: () => const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildBody(SalesState state) {
    if (state.isLoading) return const LoadingView();

    if (state.error != null && state.items.isEmpty) {
      return ErrorView(
        message: state.error!,
        onRetry: () =>
            ref.read(salesControllerProvider.notifier).loadFirstPage(),
      );
    }

    if (state.items.isEmpty) {
      return const EmptyView(
        message: 'Nema prodaja.',
        icon: Icons.point_of_sale,
      );
    }

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(salesControllerProvider.notifier).loadFirstPage(),
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
          final s = state.items[index];
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                child: Icon(
                  s.isInternal ? Icons.person_outline : Icons.point_of_sale,
                ),
              ),
              title: Row(
                children: [
                  Text('${s.items.length} stavki'),
                  if (s.isInternal) ...[
                    const SizedBox(width: 8),
                    const _InternalBadge(),
                  ],
                ],
              ),
              subtitle: Text(Format.dateTime(s.createdAt)),
              trailing: Text(
                Format.money(s.total),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SaleDetailScreen(saleId: s.id!),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Mala oznaka „Interno“ za prodaje koje je barber uzeo za ličnu upotrebu.
class _InternalBadge extends StatelessWidget {
  const _InternalBadge();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.tertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Interno',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
