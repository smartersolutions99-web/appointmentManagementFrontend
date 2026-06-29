import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_service.dart';
import 'auth_controller.dart';
import 'dio_client.dart';
import 'token_storage.dart';

/// Ovdje su „provideri“ za osnovne servise. Provider je Riverpod-ov način
/// da jednu instancu (npr. ApiService) napravi jednom i dijeli kroz aplikaciju.

/// Sigurno skladište tokena.
final tokenStorageProvider = Provider<TokenStorage>((ref) {
  return TokenStorage();
});

/// Podešen Dio klijent (sa auth interceptorom).
///
/// Kada sesija istekne, pozivamo [AuthController.handleSessionExpired] da
/// aplikacija vrati korisnika na ekran za prijavu. Poziv je „lijen“ (izvršava
/// se tek kada zatreba), pa nema problema sa međusobnom zavisnošću providera.
final dioProvider = Provider((ref) {
  final tokenStorage = ref.watch(tokenStorageProvider);
  return buildDioClient(
    tokenStorage,
    onSessionExpired: () => ref.read(authControllerProvider).handleSessionExpired(),
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
