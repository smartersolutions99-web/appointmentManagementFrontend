import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/config.dart';

// Stvarno preuzimanje i instalacija zavise od platforme (koriste `dart:io`,
// koji ne postoji na webu). Zato uvozimo „stub" verziju, a na Android/Windows
// (gdje `dart.library.io` postoji) automatski se uvozi prava implementacija.
// Isti obrazac kao kod `file_download.dart`.
import 'update_installer_stub.dart'
    if (dart.library.io) 'update_installer_io.dart';

/// Podaci o dostupnoj nadogradnji (rezultat provjere na serveru/GitHub-u).
class UpdateInfo {
  /// `true` → obavezna nadogradnja: korisnik NE može preskočiti (nema „Kasnije").
  final bool mandatory;

  /// Naziv najnovije verzije, npr. "1.1.0" (za prikaz korisniku).
  final String latestVersion;

  /// Direktan link za preuzimanje instalacionog fajla (APK ili Windows .exe).
  final String downloadUrl;

  /// Kratak opis šta je novo (opciono; prikazuje se u dijalogu).
  final String notes;

  UpdateInfo({
    required this.mandatory,
    required this.latestVersion,
    required this.downloadUrl,
    required this.notes,
  });
}

/// Poredi dvije verzije oblika "1.2.3".
///
/// Vraća negativan broj ako je `a` starija, 0 ako su iste, pozitivan ako je
/// `a` novija. Poredimo dio-po-dio kao BROJEVE (da "1.10.0" bude novije od
/// "1.9.0", što poređenje teksta ne bi ispravno uradilo).
int _compareVersions(String a, String b) {
  List<int> parts(String v) => v
      .split('+') // odbaci eventualni "+build" sufiks
      .first
      .trim()
      .split('.')
      .map((p) => int.tryParse(p.trim()) ?? 0)
      .toList();

  final pa = parts(a);
  final pb = parts(b);
  final len = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < len; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x - y;
  }
  return 0;
}

/// Provjerava da li postoji novija verzija za TRENUTNU platformu.
///
/// Vraća `UpdateInfo` ako treba ažurirati, ili `null` ako je sve u redu
/// (već najnovija verzija, web, nepodržana platforma, ili greška u mreži).
/// Greška u provjeri NIKAD ne smije da blokira korisnika — zato „gutamo"
/// izuzetke i vraćamo `null`.
Future<UpdateInfo?> checkForUpdate() async {
  // Web se sam ažurira (svaki put učita najnoviju verziju sa Vercel-a).
  if (kIsWeb) return null;

  // Podržane su samo platforme na koje ručno distribuiramo fajl.
  final isAndroid = defaultTargetPlatform == TargetPlatform.android;
  final isWindows = defaultTargetPlatform == TargetPlatform.windows;
  if (!isAndroid && !isWindows) return null;

  try {
    // Dohvati manifest (bez našeg auth-tokena — to je javni fajl na GitHub-u).
    // Dodajemo `?t=...` da zaobiđemo keširanje i uvijek dobijemo svjež fajl.
    final dio = Dio();
    final url =
        '${AppConfig.updateManifestUrl}?t=${DateTime.now().millisecondsSinceEpoch}';
    final res = await dio.get<String>(
      url,
      options: Options(responseType: ResponseType.plain),
    );

    final data = jsonDecode(res.data ?? '{}') as Map<String, dynamic>;
    final section =
        data[isAndroid ? 'android' : 'windows'] as Map<String, dynamic>?;
    if (section == null) return null;

    final latest = (section['latestVersion'] ?? '').toString();
    final min = (section['minVersion'] ?? latest).toString();
    final downloadUrl = (section['url'] ?? '').toString();
    final notes = (data['notes'] ?? '').toString();
    if (latest.isEmpty || downloadUrl.isEmpty) return null;

    // Koja je verzija TRENUTNO instalirana (čita se iz same aplikacije).
    final info = await PackageInfo.fromPlatform();
    final current = info.version; // npr. "1.0.0"

    // Već imamo najnoviju (ili noviju) → nema ništa da se radi.
    if (_compareVersions(current, latest) >= 0) return null;

    // Ako je trenutna verzija starija od minimalno dozvoljene → obavezno.
    final mandatory = _compareVersions(current, min) < 0;

    return UpdateInfo(
      mandatory: mandatory,
      latestVersion: latest,
      downloadUrl: downloadUrl,
      notes: notes,
    );
  } catch (_) {
    return null; // bilo kakva greška → tiho odustani, ne diraj korisnika
  }
}

/// Preuzima instalacioni fajl i pokreće instalaciju.
///
/// - Android: preuzme APK pa ga otvori → sistem pokrene instalaciju.
/// - Windows: preuzme .exe instaler, pokrene ga i zatvori aplikaciju (da
///   instaler može zamijeniti fajlove).
///
/// `onProgress` prijavljuje napredak preuzimanja kao broj 0.0–1.0.
Future<void> startUpdate({
  required String url,
  required void Function(double progress) onProgress,
}) {
  return downloadAndInstall(url: url, onProgress: onProgress);
}
