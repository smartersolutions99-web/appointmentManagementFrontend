import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../services/providers.dart';

/// Lista proizvoda sa servera.
final productsProvider = FutureProvider<List<ProductResponse>>((ref) {
  return ref.watch(apiServiceProvider).getProducts();
});

/// Lista dobavljača (za padajuću listu pri unosu proizvoda).
/// Endpoint je sada paginiran — za padajuću listu povučemo prvu veliku stranicu.
final suppliersProvider = FutureProvider<List<SupplierResponse>>((ref) async {
  final page = await ref.watch(apiServiceProvider).getSuppliers(
        page: 0,
        size: 200,
        sort: 'name,asc',
      );
  return page.content;
});
