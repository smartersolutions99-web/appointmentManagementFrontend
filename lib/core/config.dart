/// Globalna podešavanja aplikacije.
///
/// Ovdje se nalazi adresa servera. Promijeni je prema svom okruženju
/// (vidi KOMANDE_I_TUTORIJAL.md, sekcija 6).
class AppConfig {
  AppConfig._(); // Privatni konstruktor — klasa se koristi samo statički.

  /// Osnovna adresa backend servera.
  ///
  /// - Produkcija (Railway): https://appointmentmanagement-production-543b.up.railway.app
  /// - Lokalno (web / iOS):  http://localhost:8080
  /// - Android emulator:     http://10.0.2.2:8080
  static const String baseUrl =
      'https://appointmentmanagement-production-543b.up.railway.app';

  /// Naziv ovog uređaja koji šaljemo serveru pri prijavi (za upravljanje sesijama).
  static const String deviceLabel = 'Flutter aplikacija';

  /// Podrazumijevana veličina stranice za paginaciju (klijenti, termini).
  static const int defaultPageSize = 20;
}
