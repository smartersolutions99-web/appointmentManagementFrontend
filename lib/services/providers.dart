import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_service.dart';
import 'auth_controller.dart';
import 'dio_client.dart';
import 'support_session.dart';
import 'token_storage.dart';

/// Ovdje su „provideri“ za osnovne servise. Provider je Riverpod-ov način
/// da jednu instancu (npr. ApiService) napravi jednom i dijeli kroz aplikaciju.

/// Sigurno skladište tokena.
final tokenStorageProvider = Provider<TokenStorage>((ref) {
  return TokenStorage();
});

/// Stanje „support mode"-a (impersonacija za SUPER_SUPER_ADMIN). Jedna instanca
/// koju dijele interceptor (bira token) i AuthController/UI.
final supportSessionProvider = Provider<SupportSession>((ref) {
  return SupportSession();
});

/// Podešen Dio klijent (sa auth interceptorom).
///
/// Kada sesija istekne, pozivamo [AuthController.handleSessionExpired] da
/// aplikacija vrati korisnika na ekran za prijavu. Poziv je „lijen“ (izvršava
/// se tek kada zatreba), pa nema problema sa međusobnom zavisnošću providera.
final dioProvider = Provider((ref) {
  final tokenStorage = ref.watch(tokenStorageProvider);
  final supportSession = ref.watch(supportSessionProvider);
  return buildDioClient(
    tokenStorage,
    supportSession,
    onSessionExpired: () =>
        ref.read(authControllerProvider).handleSessionExpired(),
    onImpersonationLost: () =>
        ref.read(authControllerProvider).handleImpersonationLost(),
  );
});

/// Retrofit API servis — preko njega zovemo sve endpointe.
final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService(ref.watch(dioProvider));
});

/// Glavni kontroler prijave/odjave i statusa sesije.
/// Koristimo ChangeNotifier jer ga GoRouter lako „sluša“ za preusmjeravanje.
final authControllerProvider = ChangeNotifierProvider<AuthController>((ref) {
  return AuthController(ref.watch(tokenStorageProvider), ref);
});
