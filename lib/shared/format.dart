import 'package:intl/intl.dart';

/// Pomoćne funkcije za formatiranje datuma i cijena na crnogorskom formatu.
class Format {
  Format._();

  // npr. "16.06.2026. 14:30"
  static final _dateTime = DateFormat('dd.MM.yyyy. HH:mm');
  // npr. "16.06.2026."
  static final _date = DateFormat('dd.MM.yyyy.');
  // npr. "14:30"
  static final _time = DateFormat('HH:mm');

  /// Datum i vrijeme (ili "—" ako je null).
  static String dateTime(DateTime? value) =>
      value == null ? '—' : _dateTime.format(value.toLocal());

  /// Samo datum.
  static String date(DateTime? value) =>
      value == null ? '—' : _date.format(value.toLocal());

  /// Samo vrijeme.
  static String time(DateTime? value) =>
      value == null ? '—' : _time.format(value.toLocal());

  // Nazivi dana u sedmici na crnogorskom (1 = ponedjeljak ... 7 = nedjelja).
  static const _weekdays = [
    'Ponedjeljak',
    'Utorak',
    'Srijeda',
    'Četvrtak',
    'Petak',
    'Subota',
    'Nedjelja',
  ];

  /// Naziv dana u sedmici (npr. "Ponedjeljak").
  static String weekday(DateTime? value) =>
      value == null ? '' : _weekdays[value.toLocal().weekday - 1];

  /// Cijena sa dvije decimale i oznakom „€“ (npr. "1.250,00 €").
  static String money(num? value) {
    final formatter = NumberFormat.currency(
      locale: 'de_DE', // koristi tačku za hiljade i zarez za decimale
      symbol: '€',
      decimalDigits: 2,
    );
    return formatter.format(value ?? 0);
  }
}
