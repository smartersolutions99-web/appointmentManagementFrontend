import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/exceptions.dart';
import '../../models/models.dart';
import '../../shared/format.dart';
import '../../shared/widgets.dart';
import '../products/product_picker.dart';
import '../products/products_provider.dart';
import 'purchase_detail_screen.dart';
import 'purchases_provider.dart';

/// Jedna stavka nabavke u formi (proizvod + količina + nabavna cijena).
class _Line {
  final ProductResponse product;
  final TextEditingController qty;
  final TextEditingController cost;

  _Line(this.product)
      : qty = TextEditingController(text: '1'),
        cost = TextEditingController(
            text: product.price != null ? '${product.price}' : '');

  int get quantity => int.tryParse(qty.text.trim()) ?? 0;
  double get unitCost =>
      double.tryParse(cost.text.trim().replaceAll(',', '.')) ?? -1;
  double get lineTotal => quantity * (unitCost < 0 ? 0 : unitCost);

  void dispose() {
    qty.dispose();
    cost.dispose();
  }
}

/// Ekran za kreiranje nove nabavke (stock-in). Dostupno oba role.
class NewPurchaseScreen extends ConsumerStatefulWidget {
  const NewPurchaseScreen({super.key});

  @override
  ConsumerState<NewPurchaseScreen> createState() => _NewPurchaseScreenState();
}

class _NewPurchaseScreenState extends ConsumerState<NewPurchaseScreen> {
  final _note = TextEditingController();
  final _lines = <_Line>[];
  int? _supplierId;
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  double get _grandTotal =>
      _lines.fold(0, (sum, l) => sum + l.lineTotal);

  Future<void> _addItem() async {
    final product = await showProductPicker(context);
    if (product == null) return;
    setState(() => _lines.add(_Line(product)));
  }

  Future<void> _submit() async {
    if (_lines.isEmpty) {
      showSnack(context, 'Dodajte bar jednu stavku.', isError: true);
      return;
    }
    // Provjeri količine (≥1) i cijene (≥0).
    for (final l in _lines) {
      if (l.quantity < 1 || l.unitCost < 0) {
        showSnack(context, 'Provjerite količine (≥1) i cijene (≥0).',
            isError: true);
        return;
      }
    }

    final request = PurchaseRequest(
      supplierId: _supplierId,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      items: [
        for (final l in _lines)
          PurchaseItemRequest(
            productId: l.product.id!,
            quantity: l.quantity,
            unitCost: l.unitCost,
          ),
      ],
    );

    setState(() => _saving = true);
    try {
      final created =
          await ref.read(purchasesControllerProvider.notifier).create(request);
      if (!mounted) return;
      showSnack(context, 'Nabavka sačuvana.');
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PurchaseDetailScreen(purchaseId: created.id!),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showSnack(context, ApiException.from(e).message, isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final suppliersAsync = ref.watch(suppliersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Nova nabavka')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Ukupno: ${Format.money(_grandTotal)}',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              FilledButton.icon(
                // Vidi objašnjenje u new_sale_screen.dart: globalna tema pravi
                // dugmad beskonačne širine, a bottomNavigationBar se u jednom
                // prolazu raspoređuje sa neograničenom širinom (animacija rute),
                // pa beskonačna širina obara layout. Vraćamo širinu „prema sadržaju“.
                style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                onPressed: _saving ? null : _submit,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: const Text('Sačuvaj'),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        children: [
          // Dobavljač (opciono).
          suppliersAsync.maybeWhen(
            data: (suppliers) => DropdownButtonFormField<int?>(
              value: _supplierId,
              decoration: const InputDecoration(
                labelText: 'Dobavljač (opciono)',
                prefixIcon: Icon(Icons.local_shipping_outlined),
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('—')),
                for (final s in suppliers)
                  DropdownMenuItem(
                      value: s.id, child: Text(s.name ?? 'Dobavljač ${s.id}')),
              ],
              onChanged: (v) => setState(() => _supplierId = v),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(height: 12),

          // Stavke.
          Row(
            children: [
              Text('Stavke', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton.icon(
                onPressed: _addItem,
                icon: const Icon(Icons.add),
                label: const Text('Dodaj stavku'),
              ),
            ],
          ),
          if (_lines.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Nema stavki. Dodajte proizvod.'),
            ),
          for (var i = 0; i < _lines.length; i++) _buildLine(i),

          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: const InputDecoration(
              labelText: 'Napomena (opciono)',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildLine(int index) {
    final line = _lines[index];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(line.product.name ?? '—',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('Linija: ${Format.money(line.lineTotal)}',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 64,
              child: TextField(
                controller: line.qty,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Kol.', isDense: true),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 90,
              child: TextField(
                controller: line.cost,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Cijena', isDense: true),
                onChanged: (_) => setState(() {}),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Ukloni',
              onPressed: () => setState(() {
                _lines.removeAt(index).dispose();
              }),
            ),
          ],
        ),
      ),
    );
  }
}
