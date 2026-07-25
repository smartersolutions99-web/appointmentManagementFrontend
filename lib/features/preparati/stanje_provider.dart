import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../services/providers.dart';

/// Period (od–do) za koji računamo „Stanje". Podrazumijevano: tekući mjesec.
///
/// Držimo ga u provideru da izbor perioda preživi prelaske između tabova.
final stanjePeriodProvider = StateProvider<DateTimeRange>((ref) {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, 1); // prvi dan mjeseca
  final end = DateTime(now.year, now.month + 1, 0); // zadnji dan mjeseca
  return DateTimeRange(start: start, end: end);
});

/// Zbir za JEDAN proizvod u periodu: koliko je nabavljeno i prodato
/// (i količinski i novčano).
class ProductStanje {
  final String name;
  int purchasedQty = 0; // nabavljeno komada
  int soldQty = 0; // prodato komada (bez internih)
  double purchasedValue = 0; // nabavka u novcu
  double soldValue = 0; // prodaja u novcu (bez internih)

  ProductStanje(this.name);
}

/// Ukupno stanje za izabrani period.
class StanjeSummary {
  final double totalPurchase; // ukupna nabavka (novac)
  final double totalSales; // ukupna prodaja (novac, bez internih)
  final double internalValue; // interno uzeto (barber za sebe) — novac
  final int purchaseCount; // broj nabavki
  final int salesCount; // broj prodaja (bez internih)
  final int internalCount; // broj internih izdavanja
  final List<ProductStanje> products; // po proizvodu (najprodavaniji gore)

  const StanjeSummary({
    required this.totalPurchase,
    required this.totalSales,
    required this.internalValue,
    required this.purchaseCount,
    required this.salesCount,
    required this.internalCount,
    required this.products,
  });

  /// Čist plus = ukupna prodaja − ukupna nabavka (za period).
  double get net => totalSales - totalPurchase;
}

/// Skupi SVE stranice nabavki/prodaja u periodu i saberi u [StanjeSummary].
///
/// `autoDispose` — kad se izađe sa taba, stanje se oslobodi; pri povratku se
/// ponovo učita. Provider „gleda" [stanjePeriodProvider], pa promjena perioda
/// automatski ponovo pokreće računanje.
final stanjeProvider = FutureProvider.autoDispose<StanjeSummary>((ref) async {
  final api = ref.watch(apiServiceProvider);
  final period = ref.watch(stanjePeriodProvider);

  // Opseg u ISO tekstu (UTC). Kao i drugdje u aplikaciji: početak = prvi dan,
  // a kraj uključuje cijeli zadnji dan (+1 dan), pa server uhvati sve unose.
  final fromIso =
      DateTime(period.start.year, period.start.month, period.start.day)
          .toUtc()
          .toIso8601String();
  final toIso =
      DateTime(period.end.year, period.end.month, period.end.day)
          .add(const Duration(days: 1))
          .toUtc()
          .toIso8601String();

  // --- Nabavke: pokupi sve stranice ---
  final purchases = <PurchaseResponse>[];
  for (var page = 0; page < 100; page++) {
    final res = await api.getPurchases(
      from: fromIso,
      to: toIso,
      page: page,
      size: 200,
      sort: 'createdAt,asc',
    );
    purchases.addAll(res.content);
    if (res.last || res.content.isEmpty) break; // gotovo
  }

  // --- Prodaje: pokupi sve stranice ---
  final sales = <SaleResponse>[];
  for (var page = 0; page < 100; page++) {
    final res = await api.getSales(
      from: fromIso,
      to: toIso,
      page: page,
      size: 200,
      sort: 'createdAt,asc',
    );
    sales.addAll(res.content);
    if (res.last || res.content.isEmpty) break;
  }

  // --- Sabiranje ---
  final byProduct = <String, ProductStanje>{};
  ProductStanje productFor(String? name, int? id) => byProduct.putIfAbsent(
        name?.trim().isNotEmpty == true ? name!.trim() : 'Proizvod ${id ?? '?'}',
        () => ProductStanje(
          name?.trim().isNotEmpty == true
              ? name!.trim()
              : 'Proizvod ${id ?? '?'}',
        ),
      );

  var totalPurchase = 0.0;
  for (final p in purchases) {
    totalPurchase += p.totalCost ?? 0;
    for (final it in p.items) {
      final ps = productFor(it.productName, it.productId);
      ps.purchasedQty += it.quantity ?? 0;
      ps.purchasedValue +=
          it.lineTotal ?? (it.unitCost ?? 0) * (it.quantity ?? 0);
    }
  }

  var totalSales = 0.0;
  var internalValue = 0.0;
  var salesCount = 0;
  var internalCount = 0;
  for (final s in sales) {
    if (s.isInternal) {
      // Interno (barber uzeo za sebe) — ne ulazi u prihod ni u „prodato".
      internalValue += s.total ?? 0;
      internalCount++;
      continue;
    }
    totalSales += s.total ?? 0;
    salesCount++;
    for (final it in s.items) {
      final ps = productFor(it.productName, it.productId);
      ps.soldQty += it.quantity ?? 0;
      ps.soldValue += it.lineTotal ?? (it.unitPrice ?? 0) * (it.quantity ?? 0);
    }
  }

  // Sortiraj: najveća prodaja gore; ako je 0, onda po nabavci.
  final products = byProduct.values.toList()
    ..sort((a, b) {
      final bySold = b.soldValue.compareTo(a.soldValue);
      return bySold != 0 ? bySold : b.purchasedValue.compareTo(a.purchasedValue);
    });

  return StanjeSummary(
    totalPurchase: totalPurchase,
    totalSales: totalSales,
    internalValue: internalValue,
    purchaseCount: purchases.length,
    salesCount: salesCount,
    internalCount: internalCount,
    products: products,
  );
});
