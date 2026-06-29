import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../services/providers.dart';

/// Lista zaposlenih sa servera.
///
/// `FutureProvider` automatski daje stanja: učitavanje / greška / podaci.
/// Kada nešto promijenimo (dodamo/obrišemo), pozovemo `ref.invalidate(...)`
/// da se lista ponovo učita.
final employeesProvider = FutureProvider<List<EmployeeResponse>>((ref) {
  return ref.watch(apiServiceProvider).getEmployees();
});

/// Lista uloga (za padajuću listu u formi).
final rolesProvider = FutureProvider<List<RoleResponse>>((ref) {
  return ref.watch(apiServiceProvider).getRoles();
});

/// Lista prodajnih mjesta (za padajuću listu u formi).
final sellingPlacesProvider = FutureProvider<List<SellingPlaceResponse>>((ref) {
  return ref.watch(apiServiceProvider).getSellingPlaces();
});
