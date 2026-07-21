import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/exceptions.dart';
import '../../models/models.dart';
import '../../services/providers.dart';
import '../../shared/format.dart';
import '../../shared/widgets.dart';
import 'product_badge.dart';
import 'product_form.dart';
import 'products_provider.dart';

/// Učitava jedan proizvod po ID-u (osvježava se nakon izmjene).
final _productProvider =
    FutureProvider.autoDispose.family<ProductResponse, int>((ref, id) {
  return ref.watch(apiServiceProvider).getProduct(id);
});

/// Detalji proizvoda. ADMIN može da izmijeni ili obriše.
class ProductDetailScreen extends ConsumerWidget {
  final int productId;

  const ProductDetailScreen({super.key, required this.productId});

  Future<void> _edit(
      BuildContext context, WidgetRef ref, ProductResponse product) async {
    final suppliers = await ref.read(suppliersProvider.future);
    if (!context.mounted) return;
    final request =
        await showProductForm(context, existing: product, suppliers: suppliers);
    if (request == null) return;
    try {
      await ref
          .read(productsControllerProvider.notifier)
          .update(productId, request);
      ref.invalidate(_productProvider(productId));
      if (context.mounted) showSnack(context, 'Sačuvano.');
    } catch (e) {
      if (context.mounted) {
        showSnack(context, ApiException.from(e).message, isError: true);
      }
    }
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, ProductResponse product) async {
    final ok = await confirmDialog(
      context,
      title: 'Brisanje proizvoda',
      message: 'Obrisati „${product.name}“?',
      confirmText: 'Obriši',
    );
    if (!ok) return;
    try {
      await ref.read(productsControllerProvider.notifier).delete(productId);
      if (context.mounted) {
        showSnack(context, 'Proizvod obrisan.');
        Navigator.of(context).pop();
      }
    } catch (e) {
      final ex = ApiException.from(e);
      final msg = ex.code == 'RESOURCE_IN_USE'
          ? 'Ovaj proizvod ima istoriju nabavki ili prodaja i ne može se obrisati.'
          : ex.message;
      if (context.mounted) showSnack(context, msg, isError: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(authControllerProvider).isAdmin;
    final async = ref.watch(_productProvider(productId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Proizvod'),
        actions: [
          if (isAdmin && async.hasValue) ...[
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Izmijeni',
              onPressed: () => _edit(context, ref, async.value!),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Obriši',
              onPressed: () => _delete(context, ref, async.value!),
            ),
          ],
        ],
      ),
      body: AsyncValueView<ProductResponse>(
        value: async,
        onRetry: () => ref.invalidate(_productProvider(productId)),
        data: (p) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    p.name ?? '—',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                QuantityBadge(quantity: p.quantity),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              child: Column(
                children: [
                  _row(Icons.sell_outlined, 'Prodajna cijena',
                      Format.money(p.finalPrice)),
                  const Divider(height: 1),
                  _row(Icons.shopping_cart_outlined, 'Nabavna cijena',
                      Format.money(p.price)),
                  const Divider(height: 1),
                  _row(Icons.local_shipping_outlined, 'Dobavljač',
                      p.supplierName ?? '—'),
                  const Divider(height: 1),
                  _row(Icons.inventory_2_outlined, 'Zaliha',
                      '${p.quantity ?? 0}'),
                  if (p.description != null && p.description!.isNotEmpty) ...[
                    const Divider(height: 1),
                    _row(Icons.notes_outlined, 'Opis', p.description!),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(value),
    );
  }
}
