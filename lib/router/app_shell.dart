import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../services/providers.dart';
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
  _NavItem(Routes.suppliers, Icons.local_shipping_outlined, 'Dobavljači'),
  _NavItem(Routes.employees, Icons.badge_outlined, 'Zaposleni', adminOnly: true),
  _NavItem(Routes.services, Icons.content_cut, 'Usluge', adminOnly: true),
  _NavItem(Routes.products, Icons.inventory_2_outlined, 'Proizvodi', adminOnly: true),
  _NavItem(Routes.reports, Icons.bar_chart_outlined, 'Izvještaji', adminOnly: true),
];

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

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              extended: MediaQuery.sizeOf(context).width >= 1100,
              selectedIndex: selectedIndex,
              onDestinationSelected: onSelect,
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Icon(Icons.cut, size: 32),
              ),
              destinations: [
                for (final item in items)
                  NavigationRailDestination(
                    icon: Icon(item.icon),
                    label: Text(item.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Scaffold(
                appBar: AppBar(
                  title: Text(currentTitle),
                  actions: [logoutButton],
                ),
                body: child,
              ),
            ),
          ],
        ),
      );
    }

    // Uski ekran (telefon).
    return Scaffold(
      appBar: AppBar(
        title: Text(currentTitle),
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
      body: child,
    );
  }
}
