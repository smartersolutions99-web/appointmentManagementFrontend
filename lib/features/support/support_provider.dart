import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../services/providers.dart';

/// Lista firmi + salona za „support" salon-picker (samo SUPER_SUPER_ADMIN).
final supportBusinessesProvider =
    FutureProvider.autoDispose<List<SupportBusiness>>((ref) {
  return ref.watch(apiServiceProvider).getSupportBusinesses();
});
