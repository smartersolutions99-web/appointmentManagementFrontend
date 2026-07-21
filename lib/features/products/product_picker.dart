import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../shared/format.dart';
import '../../shared/widgets.dart';
import 'product_badge.dart';
import 'products_provider.dart';

/// Otvara dijalog za biranje proizvoda (sa pretragom). Vraća izabrani
/// [ProductResponse] ili `null` ako je otkazano. Koristi se u nabavkama/prodajama.
Future<ProductResponse?> showProductPicker(BuildContext context) {
  return showDialog<ProductResponse>(
    context: context,
    builder: (_) => const _ProductPickerDialog(),
  );
}

class _ProductPickerDialog extends ConsumerStatefulWidget {
  const _ProductPickerDialog();

  @override
  ConsumerState<_ProductPickerDialog> createState() =>
      _ProductPickerDialogState();
}

class _ProductPickerDialogState extends ConsumerState<_ProductPickerDialog> {
  final _controller = TextEditingController();
  String _query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(productSearchProvider(_query));
    return AlertDialog(
      title: const Text('Izaberi proizvod'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Pretraga po nazivu…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: _onChanged,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: AsyncValueView<List<ProductResponse>>(
                value: results,
                onRetry: () =>
                    ref.invalidate(productSearchProvider(_query)),
                data: (products) {
                  if (products.isEmpty) {
                    return const EmptyView(
                      message: 'Nema proizvoda.',
                      icon: Icons.inventory_2_outlined,
                    );
                  }
                  return ListView.builder(
                    itemCount: products.length,
                    itemBuilder: (context, i) {
                      final p = products[i];
                      return ListTile(
                        dense: true,
                        title: Text(p.name ?? '—'),
                        subtitle: Text(Format.money(p.finalPrice)),
                        trailing: QuantityBadge(quantity: p.quantity),
                        onTap: () => Navigator.of(context).pop(p),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Otkaži'),
        ),
      ],
    );
  }
}
