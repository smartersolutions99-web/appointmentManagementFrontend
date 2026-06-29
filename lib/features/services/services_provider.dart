import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../services/providers.dart';

/// Lista usluga sa servera (npr. šišanje, farbanje...).
final servicesProvider = FutureProvider<List<ServiceEntityResponse>>((ref) {
  return ref.watch(apiServiceProvider).getServices();
});
