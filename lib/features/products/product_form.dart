import 'package:flutter/material.dart';

import '../../models/models.dart';

/// Forma za proizvod (naziv, cijene, dobavljač, opis). Vraća [ProductRequest]
/// ili `null` ako je otkazano. Otvara je samo ADMIN (gating je na ekranu).
///
/// Zalihu NE unosimo ovdje — ona se mijenja samo kroz nabavke/prodaje.
Future<ProductRequest?> showProductForm(
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

  double? parsePrice(String v) => double.tryParse(v.replaceAll(',', '.'));

  // Validator za cijenu: prazno je dozvoljeno, ali ako je uneseno mora biti ≥ 0.
  String? priceValidator(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    final n = parsePrice(t);
    if (n == null || n < 0) return 'Unesite ispravan broj (≥ 0)';
    return null;
  }

  return showDialog<ProductRequest>(
    context: context,
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
                    validator: priceValidator,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: finalPrice,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(labelText: 'Prodajna cijena (€)'),
                    validator: priceValidator,
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
