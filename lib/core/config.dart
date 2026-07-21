import 'package:flutter/foundation.dart' show kIsWeb;

/// Globalna podešavanja aplikacije.
///
/// Ovdje se nalazi adresa servera. Promijeni je prema svom okruženju
/// (vidi KOMANDE_I_TUTORIJAL.md, sekcija 6).
class AppConfig {
  AppConfig._(); // Privatni konstruktor — klasa se koristi samo statički.

  /// Produkcijski backend (Railway).
  static const String _railwayUrl =
      'https://appointmentmanagement-production-543b.up.railway.app';

  /// Osnovna adresa backend servera.
  ///
  /// - Desktop / Android / iOS: puna Railway adresa.
  /// - Web (Vercel): koristi ISTI domen kao sajt (npr. https://tvoj-app.vercel.app),
  ///   pa pozivi idu na `/api/...` na tom domenu, a Vercel ih proksira na Railway
  ///   (vidi `vercel.json` u korijenu projekta). Time browser vidi „isti domen"
  ///   pa NEMA CORS problema — bez ikakvih izmjena backenda.
  ///
  /// Napomena za lokalni web-dev (`flutter run -d chrome`): tu nema Vercel
  /// proksija, pa web-dev radi samo ako backend dozvoli CORS ili ako testiraš
  /// već deployovanu verziju. Za razvoj koristi desktop (`flutter run -d windows`).
  static String get baseUrl => kIsWeb ? Uri.base.origin : _railwayUrl;

  /// Naziv ovog uređaja koji šaljemo serveru pri prijavi (za upravljanje sesijama).
  static const String deviceLabel = 'Flutter aplikacija';

  /// Podrazumijevana veličina stranice za paginaciju (klijenti, termini).
  static const int defaultPageSize = 20;
}
