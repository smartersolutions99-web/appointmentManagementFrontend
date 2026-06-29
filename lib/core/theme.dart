import 'package:flutter/material.dart';

/// Definicija izgleda aplikacije (Material 3).
///
/// Koristimo jednu „sjemensku“ boju (seed) iz koje Flutter automatski
/// generiše usklađenu paletu boja za cijelu aplikaciju.
class AppTheme {
  AppTheme._();

  /// Glavna boja brenda (ljubičasto/indigo — moderno i neutralno za salon).
  static const Color _seedColor = Color(0xFF6750A4);

  /// Svijetla tema.
  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.light,
    );

    return _baseTheme(colorScheme);
  }

  /// Tamna tema (automatski se koristi ako uređaj radi u „dark mode“).
  static ThemeData dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
    );

    return _baseTheme(colorScheme);
  }

  /// Zajednička podešavanja za obje teme — da se ne ponavlja kod.
  static ThemeData _baseTheme(ColorScheme colorScheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,

      // Zaobljena polja za unos teksta sa lijepim okvirom.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),

      // Zaobljena, prozračna dugmad.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      appBarTheme: const AppBarTheme(centerTitle: false),
    );
  }
}
