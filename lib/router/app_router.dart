import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/appointments/appointments_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/password_gate.dart';
import '../features/customers/customers_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/employees/employees_screen.dart';
import '../features/preparati/preparati_screen.dart';
import '../features/products/products_screen.dart';
import '../features/purchases/purchases_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/sales/sales_screen.dart';
import '../features/services/services_screen.dart';
import '../features/shifts/shift_assignments_screen.dart';
import '../features/shifts/shift_templates_screen.dart';
import '../features/shifts/working_hours_screen.dart';
import '../features/suppliers/suppliers_screen.dart';
import '../services/auth_controller.dart';
import '../services/providers.dart';
import 'app_shell.dart';

/// Sve putanje (rute) na jednom mjestu — da izbjegnemo greške u kucanju.
class Routes {
  static const login = '/login';
  static const dashboard = '/';
  static const customers = '/customers';
  static const employees = '/employees';
  static const services = '/services';
  static const products = '/products';
  static const suppliers = '/suppliers';
  static const purchases = '/purchases';
  static const sales = '/sales';
  static const preparati = '/preparati';
  static const appointments = '/appointments';
  static const workingHours = '/working-hours';
  static const shiftTemplates = '/shift-templates';
  static const shiftAssignments = '/shift-assignments';
  static const reports = '/reports';
}

/// Provider koji pravi GoRouter i povezuje ga sa stanjem prijave.
final routerProvider = Provider<GoRouter>((ref) {
  // Kontroler prijave je ChangeNotifier, pa ga GoRouter može „slušati“:
  // kad se promijeni status (prijava/odjava), router ponovo izračuna rutu.
  final auth = ref.watch(authControllerProvider);

  return GoRouter(
    initialLocation: Routes.dashboard,
    refreshListenable: auth,

    // `redirect` se poziva pri svakoj navigaciji i odlučuje gdje smije korisnik.
    redirect: (context, state) {
      final status = auth.status;
      final goingToLogin = state.matchedLocation == Routes.login;

      // Dok ne znamo status (na startu), ne preusmjeravamo.
      if (status == AuthStatus.unknown) return null;

      final loggedOut = status == AuthStatus.unauthenticated;

      // Nije prijavljen, a ne ide na login → pošalji ga na login.
      if (loggedOut && !goingToLogin) return Routes.login;

      // Prijavljen je, a otišao bi na login → vrati ga na početnu.
      if (!loggedOut && goingToLogin) return Routes.dashboard;

      // Zaštita stranica koje smije samo administrator.
      final adminOnly = {
        Routes.employees,
        Routes.services,
        Routes.workingHours,
        Routes.shiftTemplates,
        Routes.shiftAssignments,
        Routes.reports,
      };
      if (!auth.isAdmin && adminOnly.contains(state.matchedLocation)) {
        return Routes.dashboard;
      }

      return null; // Sve u redu — pusti navigaciju.
    },

    routes: [
      // Ekran za prijavu je izvan glavnog „okvira“ (nema meni).
      GoRoute(
        path: Routes.login,
        builder: (context, state) => const LoginScreen(),
      ),

      // ShellRoute: zajednički okvir (meni + AppBar) oko svih glavnih ekrana.
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: Routes.dashboard,
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: Routes.customers,
            builder: (context, state) => const CustomersScreen(),
          ),
          GoRoute(
            path: Routes.employees,
            builder: (context, state) => const PasswordGate(
              title: 'Zaposleni',
              child: EmployeesScreen(),
            ),
          ),
          GoRoute(
            path: Routes.services,
            builder: (context, state) => const ServicesScreen(),
          ),
          GoRoute(
            path: Routes.preparati,
            builder: (context, state) => const PreparatiScreen(),
          ),
          GoRoute(
            path: Routes.products,
            builder: (context, state) => const ProductsScreen(),
          ),
          GoRoute(
            path: Routes.suppliers,
            builder: (context, state) => const SuppliersScreen(),
          ),
          GoRoute(
            path: Routes.purchases,
            builder: (context, state) => const PurchasesScreen(),
          ),
          GoRoute(
            path: Routes.sales,
            builder: (context, state) => const SalesScreen(),
          ),
          GoRoute(
            path: Routes.appointments,
            builder: (context, state) => const AppointmentsScreen(),
          ),
          GoRoute(
            path: Routes.workingHours,
            builder: (context, state) => const WorkingHoursScreen(),
          ),
          GoRoute(
            path: Routes.shiftTemplates,
            builder: (context, state) => const ShiftTemplatesScreen(),
          ),
          GoRoute(
            path: Routes.shiftAssignments,
            builder: (context, state) => const ShiftAssignmentsScreen(),
          ),
          GoRoute(
            path: Routes.reports,
            builder: (context, state) => const PasswordGate(
              title: 'Izvještaji',
              child: ReportsScreen(),
            ),
          ),
        ],
      ),
    ],
  );
});
