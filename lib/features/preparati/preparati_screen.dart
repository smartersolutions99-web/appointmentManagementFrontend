import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/providers.dart';
import '../products/products_screen.dart';
import '../purchases/purchases_screen.dart';
import '../sales/sales_screen.dart';
import '../suppliers/suppliers_screen.dart';
import 'stanje_tab.dart';

/// Jedan tab: naziv + ekran koji se prikazuje.
class _TabDef {
  final String label;
  final Widget view;
  const _TabDef(this.label, this.view);
}

/// „Preparati" — objedinjena stranica sa tabovima za sve oko robe:
/// Nabavka · Proizvodi · Prodaja · Dobavljači, plus „Stanje" (samo ADMIN).
///
/// Postojeće ekrane samo ugnježđujemo kao tabove — svaki zadrži svoje „+"
/// dugme (FloatingActionButton) jer i dalje ima svoj Scaffold.
class PreparatiScreen extends ConsumerWidget {
  const PreparatiScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(authControllerProvider).isAdmin;

    // Zaposleni (ne-admin) ima pristup SAMO tabu „Proizvodi". Nabavka, Prodaja,
    // Dobavljači i Stanje sadrže osjetljive podatke (nabavne cijene, profit) pa
    // ih vidi samo administrator.
    final tabs = <_TabDef>[
      if (isAdmin) const _TabDef('Nabavka', PurchasesScreen()),
      const _TabDef('Proizvodi', ProductsScreen()),
      if (isAdmin) const _TabDef('Prodaja', SalesScreen()),
      if (isAdmin) const _TabDef('Dobavljači', SuppliersScreen()),
      // „Stanje" (finansije/profit) vidi samo administrator.
      if (isAdmin) const _TabDef('Stanje', StanjeTab()),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Column(
        children: [
          Material(
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.4),
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [for (final t in tabs) Tab(text: t.label)],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [for (final t in tabs) t.view],
            ),
          ),
        ],
      ),
    );
  }
}
