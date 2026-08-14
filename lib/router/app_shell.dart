import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../features/appointments/reminders.dart';
import '../features/update/update_gate.dart';
import '../services/providers.dart';
import '../services/update_service.dart';
import 'app_router.dart';

/// Jedna stavka u meniju.
class _NavItem {
  final String route;
  final IconData icon;
  final String label;
  final bool adminOnly; // Da li je vidljiva samo administratoru.

  const _NavItem(this.route, this.icon, this.label, {this.adminOnly = false});
}

/// Sve stavke menija. Redoslijed = redoslijed u meniju.
const _allItems = <_NavItem>[
  _NavItem(Routes.dashboard, Icons.dashboard_outlined, 'Početna'),
  _NavItem(Routes.appointments, Icons.event_outlined, 'Termini'),
  _NavItem(Routes.customers, Icons.people_outline, 'Klijenti'),
  // „Preparati" objedinjuje: Nabavka, Proizvodi, Prodaja, Dobavljači (+ Stanje).
  _NavItem(Routes.preparati, Icons.inventory_2_outlined, 'Preparati'),
  _NavItem(Routes.employees, Icons.badge_outlined, 'Zaposleni', adminOnly: true),
  _NavItem(Routes.services, Icons.content_cut, 'Usluge', adminOnly: true),
  // Radno vrijeme, Šabloni smjena i Dodjela smjena: zaposleni ih vidi u režimu
  // „samo pregled" (bez izmjena) — zato NISU više adminOnly.
  _NavItem(Routes.workingHours, Icons.access_time, 'Radno vrijeme'),
  _NavItem(Routes.shiftTemplates, Icons.calendar_view_week, 'Šabloni smjena'),
  _NavItem(Routes.shiftAssignments, Icons.assignment_ind_outlined,
      'Dodjela smjena'),
  _NavItem(Routes.suspicious, Icons.report_gmailerrorred_outlined,
      'Sumnjivi termini',
      adminOnly: true),
  _NavItem(Routes.reports, Icons.bar_chart_outlined, 'Izvještaji', adminOnly: true),
  // „Bakšiš" vidi svako (zaposleni vidi/unosi samo svoje — backend to čuva).
  _NavItem(Routes.tips, Icons.savings_outlined, 'Bakšiš'),
];

/// Da li je bočni meni proširen (ikonice + tekst) ili skupljen (samo ikonice).
/// Čuvamo ga u provideru da izbor ostane zapamćen dok se krećemo kroz ekrane.
final railExtendedProvider = StateProvider<bool>((ref) => true);

/// Verzija aplikacije (npr. "1.2.0") — čita se iz same aplikacije i prikazuje
/// pored naslova (lako se vidi koja je verzija instalirana).
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.version;
});

/// Provjera nadogradnje. Riverpod pokreće ovo JEDNOM i kešira rezultat, pa je
/// otporno na ponovno građenje widgeta (za razliku od okidača u `initState`).
final updateCheckProvider = FutureProvider<UpdateInfo?>((ref) async {
  return checkForUpdate();
});

/// Da se dijalog nadogradnje prikaže samo jednom po pokretanju aplikacije.
bool _updateDialogShown = false;

/// Zajednički „okvir“ oko svih glavnih ekrana: bočni meni + naslovna traka.
///
/// Na širokim ekranima prikazuje bočnu traku (NavigationRail), a na uskim
/// (telefon) koristi „hamburger“ meni (Drawer). Tako je prilagodljiv.
class AppShell extends ConsumerWidget {
  final Widget child; // Trenutni ekran (mijenja ga GoRouter).

  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);

    // Filtriramo meni prema ulozi (role-based navigacija).
    final items = _allItems
        .where((item) => !item.adminOnly || auth.isAdmin)
        .toList();

    // Pronađi koja je stavka trenutno aktivna (na osnovu putanje u URL-u).
    final location = GoRouterState.of(context).matchedLocation;
    var selectedIndex = items.indexWhere((i) => i.route == location);
    if (selectedIndex < 0) selectedIndex = 0;

    final currentTitle = items[selectedIndex].label;

    // Uz naslov pokaži i verziju aplikacije (npr. „Početna · v1.2.0").
    final version = ref.watch(appVersionProvider).value ?? '';
    final titleText =
        version.isEmpty ? currentTitle : '$currentTitle  ·  v$version';

    // Nadogradnja: kad provjera stigne i ima novije verzije, prikaži dijalog
    // (samo jednom po pokretanju). Pošto ovo prati provider, radi bez obzira
    // na to koliko se puta AppShell pregradi nakon prijave.
    final updateInfo = ref.watch(updateCheckProvider).value;
    if (updateInfo != null && !_updateDialogShown) {
      _updateDialogShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showUpdateDialog(context, updateInfo);
      });
    }

    // Široki ekran (tablet/desktop) → bočna traka. Uski (telefon) → drawer.
    final isWide = MediaQuery.sizeOf(context).width >= 800;

    void onSelect(int index) {
      context.go(items[index].route);
      // Na uskom ekranu zatvori drawer nakon izbora.
      if (!isWide) Navigator.of(context).maybePop();
    }

    final logoutButton = IconButton(
      tooltip: 'Odjavi se',
      icon: const Icon(Icons.logout),
      onPressed: () => ref.read(authControllerProvider).logout(),
    );

    // U „support modu" (SUPER_SUPER_ADMIN impersonira salon) iznad sadržaja
    // stoji jasno obojen baner sa nazivom salona i akcijama.
    Widget mainBody = RemindersController(child: child);
    if (auth.impersonating) {
      mainBody = Column(
        children: [const _SupportBanner(), Expanded(child: mainBody)],
      );
    }

    if (isWide) {
      // Da li je bočna traka trenutno proširena (tekst uz ikonice).
      final isExtended = ref.watch(railExtendedProvider);

      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              extended: isExtended,
              selectedIndex: selectedIndex,
              onDestinationSelected: onSelect,
              // Vrh trake: logo + dugme za skupljanje/proširenje menija.
              leading: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Icon(Icons.cut, size: 32),
                  ),
                  IconButton(
                    tooltip: isExtended ? 'Skupi meni' : 'Proširi meni',
                    icon: Icon(isExtended ? Icons.menu_open : Icons.menu),
                    onPressed: () => ref
                        .read(railExtendedProvider.notifier)
                        .state = !isExtended,
                  ),
                  const SizedBox(height: 8),
                ],
              ),
              destinations: [
                for (final item in items)
                  NavigationRailDestination(
                    // Kad je traka skupljena, vidi se samo ikonica — pa na hover
                    // preko ikonice pokazujemo tooltip sa nazivom stavke.
                    // Kad je proširena, naziv već stoji pored, pa tooltip ne treba.
                    icon: isExtended
                        ? Icon(item.icon)
                        : Tooltip(
                            message: item.label,
                            child: Icon(item.icon),
                          ),
                    label: Text(item.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Scaffold(
                appBar: AppBar(
                  title: Text(titleText),
                  actions: [logoutButton],
                ),
                body: mainBody,
              ),
            ),
          ],
        ),
      );
    }

    // Uski ekran (telefon).
    return Scaffold(
      appBar: AppBar(
        title: Text(titleText),
        actions: [logoutButton],
      ),
      drawer: NavigationDrawer(
        selectedIndex: selectedIndex,
        onDestinationSelected: onSelect,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(28, 24, 16, 12),
            child: Text('Salon Menadžment',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          for (final item in items)
            NavigationDrawerDestination(
              icon: Icon(item.icon),
              label: Text(item.label),
            ),
        ],
      ),
      body: mainBody,
    );
  }
}

/// Baner „support moda" (SUPER_SUPER_ADMIN impersonira salon) — jasno drugačija
/// boja + naziv salona i akcije „Promijeni salon" / „Izađi".
class _SupportBanner extends ConsumerWidget {
  const _SupportBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final theme = Theme.of(context);
    final fg = theme.colorScheme.onTertiary;
    final where = [
      if ((auth.supportBusinessName ?? '').isNotEmpty)
        auth.supportBusinessName!,
      if ((auth.supportSellingPlaceName ?? '').isNotEmpty)
        auth.supportSellingPlaceName!,
    ].join(' › ');

    return Material(
      color: theme.colorScheme.tertiary,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Row(
            children: [
              Icon(Icons.build_circle, size: 18, color: fg),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '🛠️ Podrška — ${where.isEmpty ? 'salon' : where}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg, fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: () => context.go(Routes.support),
                style: TextButton.styleFrom(foregroundColor: fg),
                child: const Text('Promijeni salon'),
              ),
              TextButton(
                onPressed: () =>
                    ref.read(authControllerProvider).exitImpersonation(),
                style: TextButton.styleFrom(foregroundColor: fg),
                child: const Text('Izađi'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
