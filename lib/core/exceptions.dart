import 'package:dio/dio.dart';

/// Naša „čista“ greška koju razumije korisnički dio aplikacije.
///
/// Umjesto da po ekranima hvatamo komplikovane Dio greške, sve pretvaramo
/// u [ApiException] sa jasnom porukom na crnogorskom jeziku.
class ApiException implements Exception {
  /// Poruka koju možemo prikazati korisniku.
  final String message;

  /// HTTP status kod (npr. 404, 500), ako postoji.
  final int? statusCode;

  /// Kod greške iz backend „envelope“-a (npr. `OUT_OF_STOCK`, `RESOURCE_IN_USE`).
  final String? code;

  /// Dodatni podaci uz grešku (npr. za `OUT_OF_STOCK`: productId/requested/available).
  final Map<String, dynamic>? details;

  ApiException(this.message, {this.statusCode, this.code, this.details});

  @override
  String toString() => message;

  /// Pretvara raznorazne greške (Dio, mreža...) u jednu razumljivu poruku.
  factory ApiException.from(Object error) {
    // Ako nije Dio greška, vrati generičku poruku.
    if (error is! DioException) {
      return ApiException('Došlo je do neočekivane greške. Pokušajte ponovo.');
    }

    final status = error.response?.statusCode;

    // Pročitaj backend „envelope“ ({code, message, details}) ako postoji.
    String? code;
    Map<String, dynamic>? details;
    final data = error.response?.data;
    if (data is Map) {
      code = data['code'] as String?;
      final d = data['details'];
      if (d is Map) details = d.cast<String, dynamic>();
    }

    // Prevodimo najčešće tipove grešaka u jasne poruke.
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return ApiException('Server ne odgovara. Provjerite internet konekciju.');
      case DioExceptionType.connectionError:
        return ApiException(
          'Nije moguće povezati se sa serverom. Provjerite adresu i konekciju.',
        );
      default:
        break;
    }

    // Ako backend pošalje jasnu poruku u envelope-u, radije nju prikažemo.
    final serverMessage =
        (data is Map && data['message'] is String) ? data['message'] as String : null;

    // Poruke na osnovu HTTP statusa. Koristimo 0 ako status nije poznat,
    // jer poređenja tipa „>= 500“ ne rade nad `null` vrijednošću.
    final message = switch (status ?? 0) {
      400 => 'Neispravan zahtjev. Provjerite unijete podatke.',
      401 => 'Sesija je istekla. Prijavite se ponovo.',
      403 => 'Nemate dozvolu za ovu radnju.',
      404 => 'Traženi podatak nije pronađen.',
      409 => 'Podatak već postoji ili je u konfliktu.',
      422 => 'Podaci nisu ispravni.',
      >= 500 => 'Greška na serveru. Pokušajte kasnije.',
      _ => 'Došlo je do greške. Pokušajte ponovo.',
    };

    return ApiException(
      serverMessage ?? message,
      statusCode: status,
      code: code,
      details: details,
    );
  }
}
