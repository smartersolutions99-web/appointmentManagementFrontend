import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../services/providers.dart';
import '../../shared/format.dart';
import '../../shared/widgets.dart';

/// Učitava jednu prodaju po ID-u (uključuje stavke).
final _saleProvider =
    FutureProvider.autoDispose.family<SaleResponse, int>((ref, id) {
  return ref.watch(apiServiceProvider).getSale(id);
});

/// Detalji prodaje: zaglavlje (ukupno, vrsta, datum, napomena) + stavke.
class SaleDetailScreen extends ConsumerWidget {
  final int saleId;

  const SaleDetailScreen({super.key, required this.saleId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_saleProvider(saleId));
    return Scaffold(
      appBar: AppBar(title: const Text('Prodaja')),
      body: AsyncValueView<SaleResponse>(
        value: async,
        onRetry: () => ref.invalidate(_saleProvider(saleId)),
        data: (s) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Banner kad je prodaja interna (barber uzeo za ličnu upotrebu).
            if (s.isInternal)
              Card(
                color: Theme.of(context)
                    .colorScheme
                    .tertiaryContainer
                    .withValues(alpha: 0.4),
                child: const ListTile(
                  leading: Icon(Icons.person_outline),
                  title: Text('Interna prodaja (barber)'),
                  subtitle: Text(
                    'Zaliha je smanjena, ali se ne računa u prihod.',
                  ),
                ),
              ),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.payments_outlined),
                    title: const Text('Ukupno'),
                    subtitle: Text(Format.money(s.total)),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.event_outlined),
                    title: const Text('Datum'),
                    subtitle: Text(Format.dateTime(s.createdAt)),
                  ),
                  if (s.note != null && s.note!.isNotEmpty) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.notes_outlined),
                      title: const Text('Napomena'),
                      subtitle: Text(s.note!),
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
                    for (final it in s.items)
                      DataRow(cells: [
                        DataCell(Text(it.productName ?? '—')),
                        DataCell(Text('${it.quantity ?? 0}')),
                        DataCell(Text(Format.money(it.unitPrice))),
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
