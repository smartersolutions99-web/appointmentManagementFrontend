import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/exceptions.dart';
import '../../models/models.dart';
import '../../services/providers.dart';
import '../../shared/widgets.dart';
import 'supplier_form.dart';
import 'suppliers_provider.dart';

/// Učitava jednog dobavljača po ID-u (osvježava se nakon izmjene).
final _supplierProvider =
    FutureProvider.autoDispose.family<SupplierResponse, int>((ref, id) {
  return ref.watch(apiServiceProvider).getSupplier(id);
});

/// Detalji dobavljača. ADMIN može da izmijeni ili obriše.
class SupplierDetailScreen extends ConsumerWidget {
  final int supplierId;

  const SupplierDetailScreen({super.key, required this.supplierId});

  Future<void> _edit(
      BuildContext context, WidgetRef ref, SupplierResponse supplier) async {
    final request = await showSupplierForm(context, existing: supplier);
    if (request == null) return;
    try {
      await ref
          .read(suppliersControllerProvider.notifier)
          .update(supplierId, request);
      ref.invalidate(_supplierProvider(supplierId));
      if (context.mounted) showSnack(context, 'Sačuvano.');
    } catch (e) {
      if (context.mounted) {
        showSnack(context, ApiException.from(e).message, isError: true);
      }
    }
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, SupplierResponse supplier) async {
    final ok = await confirmDialog(
      context,
      title: 'Brisanje dobavljača',
      message: 'Obrisati „${supplier.name}“?',
      confirmText: 'Obriši',
    );
    if (!ok) return;
    try {
      await ref.read(suppliersControllerProvider.notifier).delete(supplierId);
      if (context.mounted) {
        showSnack(context, 'Dobavljač obrisan.');
        Navigator.of(context).pop();
      }
    } catch (e) {
      final ex = ApiException.from(e);
      // Server vraća 409 RESOURCE_IN_USE ako dobavljač ima vezane podatke.
      final msg = ex.code == 'RESOURCE_IN_USE'
          ? 'Dobavljač se koristi (proizvodi ili nabavke) i ne može se obrisati.'
          : ex.message;
      if (context.mounted) showSnack(context, msg, isError: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(authControllerProvider).isAdmin;
    final async = ref.watch(_supplierProvider(supplierId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dobavljač'),
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
      body: AsyncValueView<SupplierResponse>(
        value: async,
        onRetry: () => ref.invalidate(_supplierProvider(supplierId)),
        data: (supplier) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.local_shipping_outlined),
                    title: const Text('Naziv'),
                    subtitle: Text(supplier.name ?? '—'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.contact_phone_outlined),
                    title: const Text('Kontakt'),
                    subtitle: Text(supplier.contactValue ?? '—'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.label_outline),
                    title: const Text('Tip kontakta'),
                    subtitle: Text(supplier.contactType ?? '—'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
