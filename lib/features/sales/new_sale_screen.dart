import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/exceptions.dart';
import '../../models/models.dart';
import '../../shared/format.dart';
import '../../shared/widgets.dart';
import '../products/product_picker.dart';
import 'sale_detail_screen.dart';
import 'sales_provider.dart';

/// Jedna stavka prodaje u formi (proizvod + količina + prodajna cijena).
///
/// Cijena je unaprijed popunjena iz `finalPrice`, ali je izmjenjiva (popust).
/// `stockError` čuva raspoloživu zalihu kada server javi `OUT_OF_STOCK` baš
/// za ovaj proizvod — tada red bojimo crveno i ispisujemo poruku ispod njega.
class _Line {
  final ProductResponse product;
  final TextEditingController qty;
  final TextEditingController price;
  int? stockError; // raspoloživa zaliha (kad je OUT_OF_STOCK), inače null

  _Line(this.product)
      : qty = TextEditingController(text: '1'),
        price = TextEditingController(
            text: product.finalPrice != null ? '${product.finalPrice}' : '');

  int get quantity => int.tryParse(qty.text.trim()) ?? 0;

  /// Unijeta cijena ili `null` ako je polje prazno (tada server koristi finalPrice).
  double? get unitPrice {
    final t = price.text.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  /// Cijena za prikaz reda: unijeta → prodajna cijena proizvoda → 0.
  double get _effectivePrice => unitPrice ?? product.finalPrice ?? 0;
  double get lineTotal => quantity * _effectivePrice;

  void dispose() {
    qty.dispose();
    price.dispose();
  }
}

/// Ekran za kreiranje nove prodaje (POS). Dostupno oba role.
class NewSaleScreen extends ConsumerStatefulWidget {
  const NewSaleScreen({super.key});

  @override
  ConsumerState<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends ConsumerState<NewSaleScreen> {
  final _note = TextEditingController();
  final _lines = <_Line>[];
  bool _isInternal = false;
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  double get _grandTotal => _lines.fold(0, (sum, l) => sum + l.lineTotal);

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
    // Provjeri količine (≥1) i cijene (ako su unijete, moraju biti ≥0).
    for (final l in _lines) {
      final price = l.unitPrice;
      if (l.quantity < 1 || (price != null && price < 0)) {
        showSnack(context, 'Provjerite količine (≥1) i cijene (≥0).',
            isError: true);
        return;
      }
    }

    final request = SaleRequest(
      isInternal: _isInternal,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      items: [
        for (final l in _lines)
          SaleItemRequest(
            productId: l.product.id!,
            quantity: l.quantity,
            unitPrice: l.unitPrice, // null → server koristi finalPrice
          ),
      ],
    );

    // Očisti prethodne oznake nedostatka zalihe prije novog pokušaja.
    setState(() {
      _saving = true;
      for (final l in _lines) {
        l.stockError = null;
      }
    });

    try {
      final created =
          await ref.read(salesControllerProvider.notifier).create(request);
      if (!mounted) return;
      showSnack(context, 'Prodaja sačuvana.');
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SaleDetailScreen(saleId: created.id!),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final ex = ApiException.from(e);
      // Nedovoljna zaliha: cijela prodaja je poništena. Označi problematičan red.
      if (ex.code == 'OUT_OF_STOCK') {
        _handleOutOfStock(ex);
      } else {
        showSnack(context, ex.message, isError: true);
      }
    }
  }

  /// Iz `details` (productId, requested, available) pronađi red i označi ga.
  void _handleOutOfStock(ApiException ex) {
    final details = ex.details;
    final productId = (details?['productId'] as num?)?.toInt();
    final available = (details?['available'] as num?)?.toInt();

    if (productId != null) {
      final idx = _lines.indexWhere((l) => l.product.id == productId);
      if (idx >= 0) {
        setState(() => _lines[idx].stockError = available ?? 0);
      }
    }
    showSnack(context, 'Nedovoljna zaliha. Prodaja nije sačuvana.',
        isError: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nova prodaja')),
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
                // Globalna tema pravi dugmad „preko cijele širine“
                // (minimumSize: Size.fromHeight → beskonačna širina). To je u redu
                // kad dugme ima ograničenu širinu, ali u traci na dnu (bottomNavigationBar)
                // ovaj ekran se u jednom prolazu raspoređuje sa NEOGRANIČENOM širinom
                // (tokom animacije otvaranja rute), pa beskonačna širina obara layout.
                // Zato ovdje širinu vraćamo na „prema sadržaju“ (minimumSize.width = 0).
                style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                onPressed: _saving ? null : _submit,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: const Text('Naplati'),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        children: [
          // Prekidač: interna prodaja (barber uzeo za ličnu upotrebu).
          Card(
            child: SwitchListTile(
              value: _isInternal,
              onChanged: (v) => setState(() => _isInternal = v),
              secondary: const Icon(Icons.person_outline),
              title: const Text('Interno (barber uzeo za sebe)'),
              subtitle: const Text(
                'Zaliha se smanjuje, ali se ne računa u prihod.',
              ),
            ),
          ),
          if (_isInternal)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Card(
                color: Theme.of(context)
                    .colorScheme
                    .tertiaryContainer
                    .withValues(alpha: 0.4),
                child: const ListTile(
                  leading: Icon(Icons.info_outline),
                  dense: true,
                  title: Text('Ova prodaja je označena kao interna.'),
                ),
              ),
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
    final hasError = line.stockError != null;
    final errorColor = Theme.of(context).colorScheme.error;

    return Card(
      // Kad nema dovoljno zalihe, uokviri red crveno da odmah upada u oči.
      shape: hasError
          ? RoundedRectangleBorder(
              side: BorderSide(color: errorColor, width: 1.5),
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                    controller: line.price,
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
            // Poruka o nedostatku zalihe (inline, ispod reda).
            if (hasError)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Samo ${line.stockError} na stanju.',
                  style: TextStyle(
                    color: errorColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
