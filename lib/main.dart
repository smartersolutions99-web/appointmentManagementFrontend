import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/theme.dart';
import 'router/app_router.dart';
import 'services/notification_service.dart';

/// Ulazna tačka aplikacije — odavde sve počinje.
Future<void> main() async {
  // Mora se pozvati prije asinhronih operacija prije `runApp`.
  WidgetsFlutterBinding.ensureInitialized();

  // Učitavamo podatke za formatiranje datuma (za naš jezik/format).
  await initializeDateFormatting('sr');

  // Inicijalizuj notifikacije-podsjetnike (na webu/desktopu je ovo no-op).
  await notificationService.init();

  // `ProviderScope` je „korijen“ za Riverpod — bez njega provideri ne rade.
  runApp(const ProviderScope(child: SalonApp()));
}

/// Glavni widget aplikacije.
class SalonApp extends ConsumerWidget {
  const SalonApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Dohvatamo router (zna sve ekrane i pravila navigacije).
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Salon Menadžment',
      debugShowCheckedModeBanner: false,

      // Uvijek tamna tema, bez obzira na podešavanje uređaja.
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,

      // Povezujemo GoRouter sa aplikacijom.
      routerConfig: router,
    );
  }
}
