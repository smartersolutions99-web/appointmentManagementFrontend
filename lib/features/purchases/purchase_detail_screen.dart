import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../services/providers.dart';
import '../../shared/format.dart';
import '../../shared/widgets.dart';

/// Učitava jednu nabavku po ID-u (uključuje stavke).
final _purchaseProvider =
    FutureProvider.autoDispose.family<PurchaseResponse, int>((ref, id) {
  return ref.watch(apiServiceProvider).getPurchase(id);
});

/// Detalji nabavke: zaglavlje (dobavljač, ukupno, napomena, datum) + stavke.
class PurchaseDetailScreen extends ConsumerWidget {
  final int purchaseId;

  const PurchaseDetailScreen({super.key, required this.purchaseId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_purchaseProvider(purchaseId));
    return Scaffold(
      appBar: AppBar(title: const Text('Nabavka')),
      body: AsyncValueView<PurchaseResponse>(
        value: async,
        onRetry: () => ref.invalidate(_purchaseProvider(purchaseId)),
        data: (p) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.local_shipping_outlined),
                    title: const Text('Dobavljač'),
                    subtitle: Text(p.supplierName ?? '—'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.payments_outlined),
                    title: const Text('Ukupno'),
                    subtitle: Text(Format.money(p.totalCost)),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.event_outlined),
                    title: const Text('Datum'),
                    subtitle: Text(Format.dateTime(p.createdAt)),
                  ),
                  if (p.note != null && p.note!.isNotEmpty) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.notes_outlined),
                      title: const Text('Napomena'),
                      subtitle: Text(p.note!),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text('Stavke', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Proizvod')),
                    DataColumn(label: Text('Količina'), numeric: true),
                    DataColumn(label: Text('Cijena'), numeric: true),
                    DataColumn(label: Text('Ukupno'), numeric: true),
                  ],
                  rows: [
                    for (final it in p.items)
                      DataRow(cells: [
                        DataCell(Text(it.productName ?? '—')),
                        DataCell(Text('${it.quantity ?? 0}')),
                        DataCell(Text(Format.money(it.unitCost))),
                        DataCell(Text(Format.money(it.lineTotal))),
                      ]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
