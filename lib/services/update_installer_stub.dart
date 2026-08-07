/// „Prazna" verzija instalacije za platforme bez `dart:io` (web).
///
/// Na webu se nadogradnja nikad ne poziva (provjera odmah vraća `null`), ali
/// nam treba ova funkcija da bi se kod uopšte kompajlirao za web.
Future<void> downloadAndInstall({
  required String url,
  required void Function(double progress) onProgress,
}) async {
  throw UnsupportedError('Nadogradnja nije podržana na ovoj platformi.');
}
