import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../router/app_router.dart';
import '../../services/notification_service.dart';
import '../../services/providers.dart';
import '../../shared/format.dart';
import '../../shared/widgets.dart';
import '../reports/reports_provider.dart';
import 'barber_stats_provider.dart';

/// Da li smo na pravom telefonu (za test-dugme notifikacija).
bool get _isMobile =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Jedna prečica (kartica) na početnoj strani.
class _ShortcutData {
  final IconData icon;
  final String label;
  final String route;

  const _ShortcutData(this.icon, this.label, this.route);
}

/// Početni ekran. Pozdravlja korisnika, prikazuje kratku statistiku prihoda
/// (samo admin) i nudi velike kartice-prečice koje POPUNE ostatak ekrana.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final theme = Theme.of(context);

    // Prečice zavise od uloge: admin vidi 4, običan zaposleni 2.
    final shortcuts = <_ShortcutData>[
      const _ShortcutData(Icons.event, 'Termini', Routes.appointments),
      const _ShortcutData(Icons.people, 'Klijenti', Routes.customers),
      if (auth.isAdmin) ...[
        const _ShortcutData(Icons.badge, 'Zaposleni', Routes.employees),
        const _ShortcutData(Icons.bar_chart, 'Izvještaji', Routes.reports),
      ],
    ];

    // Cijela strana je Column koji popunjava ekran (bez skrolovanja).
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ----- Zaglavlje -----
          Text('Dobrodošli 👋', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'Uloga: ${auth.role ?? 'korisnik'}',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
          ),
          const SizedBox(height: 16),

          // ----- Prihod (samo admin) -----
          if (auth.isAdmin) ...[
            const _RevenueCard(),
            const SizedBox(height: 16),
          ],

          // ----- Statistika dana (samo barber / ne-admin) -----
          if (!auth.isAdmin) ...[
            const _BarberStatsCard(),
            const SizedBox(height: 16),
          ],

          // ----- Test notifikacija (privremeno, samo na telefonu) -----
          if (_isMobile) ...[
            const _NotificationTestButton(),
            const SizedBox(height: 16),
          ],

          Text('Brze prečice', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),

          // ----- Kartice koje popunjavaju ostatak ekrana -----
          // `Expanded` daje mreži svu preostalu visinu, pa nema skrolovanja.
          Expanded(child: _ShortcutsGrid(items: shortcuts)),
        ],
      ),
    );
  }
}

/// Mreža kartica-prečica koja popunjava raspoloživi prostor.
///
/// Broj kolona računamo prema broju kartica, a sve kartice su jednake veličine
/// jer koristimo `Expanded` i u redovima (širina) i u kolonama (visina).
class _ShortcutsGrid extends StatelessWidget {
  final List<_ShortcutData> items;

  const _ShortcutsGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    const spacing = 12.0;

    if (items.isEmpty) return const SizedBox.shrink();

    // Broj kolona prema broju kartica:
    //  1 kartica -> 1 kolona, 2-4 kartice -> 2 kolone, 5+ -> 3 kolone.
    final columns = items.length <= 1 ? 1 : (items.length <= 4 ? 2 : 3);
    // Broj redova = zaokruženo naviše (npr. 4 kartice / 2 kolone = 2 reda).
    final rows = (items.length / columns).ceil();

    return Column(
      children: [
        for (var r = 0; r < rows; r++) ...[
          if (r > 0) const SizedBox(height: spacing),
          // Svaki red dobija jednak dio visine.
          Expanded(
            child: Row(
              children: [
                for (var c = 0; c < columns; c++) ...[
                  if (c > 0) const SizedBox(width: spacing),
                  // Svaka ćelija dobija jednak dio širine.
                  Expanded(
                    child: _buildCell(r * columns + c),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Vraća karticu za dati indeks, ili prazno mjesto (da širine ostanu jednake
  /// kada poslednji red nije popunjen do kraja).
  Widget _buildCell(int index) {
    if (index >= items.length) return const SizedBox.shrink();
    return _ShortcutCard(item: items[index]);
  }
}

/// Velika kartica-prečica sa ikonicom i nazivom (popunjava svoju ćeliju).
class _ShortcutCard extends StatelessWidget {
  final _ShortcutData item;

  const _ShortcutCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: () => context.go(item.route),
        borderRadius: BorderRadius.circular(16),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.icon, size: 44, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text(item.label, style: theme.textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}

/// Privremeno dugme: dijagnostika notifikacija. Provjeri platformu, dozvolu,
/// pošalji odmah + zakazano za 10s, i ISPIŠI rezultat u dijalogu (da vidimo
/// tačno šta ne radi na ovom telefonu).
class _NotificationTestButton extends StatelessWidget {
  const _NotificationTestButton();

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.notifications_active_outlined, size: 18),
      label: const Text('Testiraj notifikaciju'),
      onPressed: () async {
        final r = StringBuffer();
        r.writeln('Platforma podržana: ${notificationService.debugSupported}');

        // Dozvola.
        try {
          final granted = await notificationService.requestPermission();
          r.writeln('Dozvola data: $granted');
        } catch (e) {
          r.writeln('Dozvola — GREŠKA: $e');
        }
        try {
          final enabled = await notificationService.areEnabled();
          r.writeln('Notifikacije uključene: $enabled');
        } catch (e) {
          r.writeln('Provjera uključenosti — GREŠKA: $e');
        }

        // Odmah.
        try {
          await notificationService.showNow(
            id: 999001,
            title: 'Test notifikacije',
            body: 'Ako vidiš ovo — radi ✅',
          );
          r.writeln('Odmah-notifikacija: poslata (bez greške)');
        } catch (e) {
          r.writeln('Odmah-notifikacija — GREŠKA: $e');
        }

        // Zakazano za 10s.
        try {
          await notificationService.scheduleStatusReminder(
            id: 999002,
            whenLocal: DateTime.now().add(const Duration(seconds: 10)),
            title: 'Test podsjetnika (10s)',
            body: 'Zakazana notifikacija ✅',
          );
          r.writeln('Zakazana (10s): poslata (bez greške)');
        } catch (e) {
          r.writeln('Zakazana — GREŠKA: $e');
        }

        if (!context.mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Dijagnostika notifikacija'),
            content: SingleChildScrollView(child: Text(r.toString())),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('U redu'),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Kartica sa prihodom salona (posljednjih 30 dana) — vidi je samo admin.
class _RevenueCard extends ConsumerWidget {
  const _RevenueCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final summaryAsync = ref.watch(last30DaysRevenueProvider);

    return AsyncValueView<RevenueSummary>(
      value: summaryAsync,
      onRetry: () => ref.invalidate(last30DaysRevenueProvider),
      data: (summary) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Prihod (30 dana)', style: theme.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(
                    Format.money(summary.totalRevenue),
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Završenih', style: theme.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text('${summary.completedAppointments}',
                      style: theme.textTheme.headlineSmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kartica sa današnjom statistikom barbera (smjena + radno vrijeme, pa broj
/// termina, završeni i sljedeći termin).
class _BarberStatsCard extends ConsumerWidget {
  const _BarberStatsCard();

  // "HH:mm:ss" → "HH:mm" (ili "—" ako fali).
  static String _hhmm(String? t) =>
      (t == null || t.length < 5) ? '—' : t.substring(0, 5);

  // "HH:mm:ss" → minuti od ponoći (ili null).
  static int? _minutes(String? t) {
    if (t == null) return null;
    final p = t.split(':');
    if (p.length < 2) return null;
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    return (h == null || m == null) ? null : h * 60 + m;
  }

  // Trajanje smjene, npr. "8h" ili "7h 30min".
  static String _durationLabel(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0 && m > 0) return '${h}h ${m}min';
    if (h > 0) return '${h}h';
    return '${m}min';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final statsAsync = ref.watch(barberTodayStatsProvider);
    // Smjena/radno vrijeme (ako je dostupno) — prikazujemo uz statistiku.
    final info = ref.watch(todayScheduleInfoProvider).valueOrNull;

    return AsyncValueView<BarberTodayStats>(
      value: statsAsync,
      onRetry: () => ref.invalidate(barberTodayStatsProvider),
      data: (stats) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Danas', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  ..._durationBadge(theme, info),
                ],
              ),
              // Smjena + radno vrijeme salona (samo ako imamo podatke).
              if (info != null) ...[
                const SizedBox(height: 12),
                _shiftLines(theme, info),
                const SizedBox(height: 14),
                Divider(height: 1, color: theme.dividerColor),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _StatItem(label: 'Termina', value: '${stats.total}'),
                  _StatItem(label: 'Završeno', value: '${stats.completed}'),
                  _StatItem(label: 'Preostalo', value: '${stats.upcoming}'),
                ],
              ),
              const SizedBox(height: 12),
              // Sljedeći termin (ako postoji).
              Row(
                children: [
                  Icon(Icons.schedule,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    stats.nextStart != null
                        ? 'Sljedeći termin u ${Format.time(stats.nextStart)}'
                        : 'Nema više zakazanih termina danas',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Bedž sa trajanjem smjene (prazno ako smjena nije poznata).
  List<Widget> _durationBadge(ThemeData theme, ScheduleDayResponse? info) {
    final s = _minutes(info?.shiftStart);
    final e = _minutes(info?.shiftEnd);
    if (s == null || e == null || e <= s) return const [];
    return [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          _durationLabel(e - s),
          style: theme.textTheme.labelLarge
              ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
        ),
      ),
    ];
  }

  /// Dvije linije: moja smjena i radno vrijeme salona.
  Widget _shiftLines(ThemeData theme, ScheduleDayResponse info) {
    final salonClosed =
        info.salonOpensAt == null || info.salonClosesAt == null;

    String shiftText;
    Color? shiftColor;
    if (info.shiftTemplateId == null) {
      shiftText = 'Smjena nije dodijeljena';
      shiftColor = theme.colorScheme.error;
    } else if (info.shiftStart == null || info.shiftEnd == null) {
      shiftText = 'Slobodan dan';
      shiftColor = theme.hintColor;
    } else {
      final name = (info.shiftTemplateName ?? '').trim();
      shiftText = 'Smjena: ${_hhmm(info.shiftStart)}–${_hhmm(info.shiftEnd)}'
          '${name.isEmpty ? '' : ' · $name'}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.badge_outlined,
                size: 18, color: shiftColor ?? theme.colorScheme.primary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                shiftText,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: shiftColor, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(salonClosed ? Icons.block : Icons.storefront_outlined,
                size: 18, color: theme.hintColor),
            const SizedBox(width: 8),
            Text(
              salonClosed
                  ? 'Salon je zatvoren danas'
                  : 'Radno vrijeme: ${_hhmm(info.salonOpensAt)}–${_hhmm(info.salonClosesAt)}',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ],
    );
  }
}

/// Jedna stavka statistike (veliki broj + naziv ispod).
class _StatItem extends StatelessWidget {
  final String label;
  final String value;

  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
