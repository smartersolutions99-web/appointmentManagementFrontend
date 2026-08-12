import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../services/providers.dart';

/// Datum u "YYYY-MM-DD" (format koji server očekuje za bakšiš).
String tipYmd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Izabrani period za pregled bakšiša. Podrazumijevano: tekući mjesec.
final tipsRangeProvider = StateProvider<DateTimeRange>((ref) {
  final now = DateTime.now();
  return DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
});

/// Ukupan bakšiš za izabrani period (GET /api/tips/total).
final tipsTotalProvider = FutureProvider.autoDispose<TipTotal>((ref) {
  final r = ref.watch(tipsRangeProvider);
  return ref
      .watch(apiServiceProvider)
      .getTipsTotal(from: tipYmd(r.start), to: tipYmd(r.end));
});

/// Zbir bakšiša po zaposlenom (GET /api/tips/summary). Employee-u backend
/// automatski vraća samo njegovo.
final tipsSummaryProvider = FutureProvider.autoDispose<List<TipSummary>>((ref) {
  final r = ref.watch(tipsRangeProvider);
  return ref
      .watch(apiServiceProvider)
      .getTipsSummary(from: tipYmd(r.start), to: tipYmd(r.end));
});

/// Lista pojedinačnih bakšiša za period (GET /api/tips).
final tipsListProvider = FutureProvider.autoDispose<List<TipResponse>>((ref) {
  final r = ref.watch(tipsRangeProvider);
  return ref
      .watch(apiServiceProvider)
      .getTips(from: tipYmd(r.start), to: tipYmd(r.end));
});

/// Osvježi sve poglede bakšiša (poslije unosa/brisanja).
void refreshTips(WidgetRef ref) {
  ref.invalidate(tipsTotalProvider);
  ref.invalidate(tipsSummaryProvider);
  ref.invalidate(tipsListProvider);
}
