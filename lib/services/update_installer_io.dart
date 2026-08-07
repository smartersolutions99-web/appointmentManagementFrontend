import 'dart:io';

import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// Prava implementacija preuzimanja + instalacije za Android i Windows.
///
/// Ovaj fajl se uvozi SAMO na platformama koje imaju `dart:io`
/// (Android/Windows/desktop). Na webu se umjesto njega koristi
/// `update_installer_stub.dart`, pa web build ne pokušava da uveze `dart:io`.
Future<void> downloadAndInstall({
  required String url,
  required void Function(double progress) onProgress,
}) async {
  // Sačuvaj fajl u privremeni folder aplikacije.
  final dir = await getTemporaryDirectory();
  final fileName = Platform.isWindows ? 'salon-update-setup.exe' : 'salon-update.apk';
  final savePath = '${dir.path}${Platform.pathSeparator}$fileName';

  // Preuzmi uz praćenje napretka (received/total → 0.0–1.0).
  final dio = Dio();
  await dio.download(
    url,
    savePath,
    onReceiveProgress: (received, total) {
      if (total > 0) onProgress(received / total);
    },
  );

  if (Platform.isAndroid) {
    // Otvaranje APK-a pokreće sistemski instaler. Korisnik potvrdi „Instaliraj".
    // (Prvi put Android traži da dozvoli instalaciju iz ove aplikacije.)
    await OpenFilex.open(savePath);
  } else if (Platform.isWindows) {
    // Pokreni instaler pa odmah zatvori aplikaciju — tako instaler može
    // slobodno zamijeniti .exe i ostale fajlove, i na kraju je opet pokrenuti.
    await Process.start(savePath, const [], mode: ProcessStartMode.detached);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    exit(0);
  }
}
