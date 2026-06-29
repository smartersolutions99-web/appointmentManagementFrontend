import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/exceptions.dart';
import '../../models/models.dart';
import '../../services/providers.dart';
import '../../shared/format.dart';
import '../../shared/widgets.dart';
import 'products_provider.dart';

/// Ekran sa listom proizvoda (CRUD), uz izbor dobavljača.
class ProductsScreen extends ConsumerWidget {
  const ProductsScreen({super.key});

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref, {
    ProductResponse? existing,
  }) async {
    // Učitaj dobavljače za padajuću listu.
    final suppliers = await ref.read(suppliersProvider.future);
    if (!context.mounted) return;

    final request = await _showProductForm(
      context,
      existing: existing,
      suppliers: suppliers,
    );
    if (request == null) return;

    final api = ref.read(apiServiceProvider);
    try {
      if (existing == null) {
        await api.createProduct(request);
      } else {
        await api.updateProduct(existing.id!, request);
      }
      ref.invalidate(productsProvider);
      if (context.mounted) showSnack(context, 'Sačuvano.');
    } catch (e) {
      if (context.mounted) {
        showSnack(context, ApiException.from(e).message, isError: true);
      }
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    ProductResponse product,
  ) async {
    final ok = await confirmDialog(
      context,
      title: 'Brisanje proizvoda',
      message: 'Obrisati „${product.name}“?',
      confirmText: 'Obriši',
    );
    if (!ok) return;
    try {
      await ref.read(apiServiceProvider).deleteProduct(product.id!);
      ref.invalidate(productsProvider);
      if (context.mounted) showSnack(context, 'Proizvod obrisan.');
    } catch (e) {
      if (context.mounted) {
        showSnack(context, ApiException.from(e).message, isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Novi proizvod'),
      ),
      body: AsyncValueView<List<ProductResponse>>(
        value: productsAsync,
        onRetry: () => ref.invalidate(productsProvider),
        data: (products) {
          if (products.isEmpty) {
            return const EmptyView(message: 'Nema proizvoda.');
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            itemCount: products.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final p = products[index];
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.inventory_2)),
                  title: Text(p.name ?? '—'),
                  subtitle: p.description == null || p.description!.isEmpty
                      ? null
                      : Text(p.description!),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        Format.money(p.finalPrice),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (v) => v == 'edit'
                            ? _openForm(context, ref, existing: p)
                            : _delete(context, ref, p),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Izmijeni')),
                          PopupMenuItem(value: 'delete', child: Text('Obriši')),
                        ],
                      ),
                    ],
                  ),
                  onTap: () => _openForm(context, ref, existing: p),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Forma za proizvod (naziv, cijene, dobavljač, opis).
Future<ProductRequest?> _showProductForm(
  BuildContext context, {
  ProductResponse? existing,
  required List<SupplierResponse> suppliers,
}) {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController(text: existing?.name ?? '');
  final price = TextEditingController(text: existing?.price?.toString() ?? '');
  final finalPrice =
      TextEditingController(text: existing?.finalPrice?.toString() ?? '');
  final description = TextEditingController(text: existing?.description ?? '');
  int? supplierId = existing?.supplierId;

  // Pomoćna funkcija za parsiranje cijene (dozvoljava i zarez).
  double? parsePrice(String v) => double.tryParse(v.replaceAll(',', '.'));

  return showDialog<ProductRequest>(
    context: context,
    // StatefulBuilder nam treba da padajuća lista može da se osvježi (setState).
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(existing == null ? 'Novi proizvod' : 'Izmijeni proizvod'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Naziv'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Obavezno polje'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: price,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(labelText: 'Nabavna cijena (€)'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: finalPrice,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(labelText: 'Prodajna cijena (€)'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: supplierId,
                    decoration: const InputDecoration(labelText: 'Dobavljač'),
                    items: [
                      for (final s in suppliers)
                        DropdownMenuItem(
                          value: s.id,
                          child: Text(s.name ?? 'Dobavljač ${s.id}'),
                        ),
                    ],
                    onChanged: (v) => setState(() => supplierId = v),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: description,
                    decoration:
                        const InputDecoration(labelText: 'Opis (opciono)'),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Otkaži'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(
                context,
                ProductRequest(
                  name: name.text.trim(),
                  price: parsePrice(price.text),
                  finalPrice: parsePrice(finalPrice.text),
                  supplierId: supplierId,
                  description: description.text.trim().isEmpty
                      ? null
                      : description.text.trim(),
                ),
              );
            },
            child: const Text('Sačuvaj'),
          ),
        ],
      ),
    ),
  );
}
