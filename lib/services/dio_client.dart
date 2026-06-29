import 'package:dio/dio.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import '../core/config.dart';
import 'auth_interceptor.dart';
import 'token_storage.dart';

/// Pravi i podešava Dio HTTP klijent.
///
/// Dio je „motor“ koji šalje zahtjeve. Ovdje mu postavljamo osnovnu adresu,
/// vremenske limite, te kačimo naš [AuthInterceptor] (tokeni + refresh) i
/// logger koji lijepo ispisuje zahtjeve u konzoli (korisno za učenje/debug).
Dio buildDioClient(
  TokenStorage tokenStorage, {
  void Function()? onSessionExpired,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      // Šaljemo i prihvatamo JSON. `contentType` je OBAVEZAN — bez njega na
      // web-u pregledač pošalje 'application/octet-stream', što server odbija.
      contentType: Headers.jsonContentType,
      headers: {'Accept': 'application/json'},
    ),
  );

  // Redoslijed je bitan: prvo auth (dodaje token), pa logger (ispis).
  dio.interceptors.add(
    AuthInterceptor(tokenStorage, onSessionExpired: onSessionExpired),
  );

  dio.interceptors.add(
    PrettyDioLogger(
      requestHeader: true,
      requestBody: true,
      responseHeader: false,
      // U pravoj produkciji logovanje obično isključimo.
    ),
  );

  return dio;
}
