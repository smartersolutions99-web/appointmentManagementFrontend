import 'package:flutter/material.dart';

import '../../services/update_service.dart';

/// Prikazuje dijalog „Dostupna je nova verzija".
///
/// - Obavezna nadogradnja: dijalog se NE može zatvoriti (nema „Kasnije", ni
///   zatvaranje dodirom pored, ni „nazad" dugmetom).
/// - Opciona: korisnik može „Kasnije" i nastaviti da radi.
///
/// Koristimo `useRootNavigator: true` da se dijalog sigurno prikaže preko
/// cijele aplikacije (bez obzira na ugniježđene navigatore go_router-a).
/// Dugmad su `TextButton` (ne `FilledButton`) da izbjegnemo globalnu temu
/// dugmadi punih širine koja zna da obori render u nekim kontekstima.
Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) {
  return showDialog<void>(
    context: context,
    barrierDismissible: !info.mandatory,
    useRootNavigator: true,
    builder: (ctx) => PopScope(
      canPop: !info.mandatory,
      child: AlertDialog(
        icon: const Icon(Icons.system_update),
        title: const Text('Dostupna je nova verzija'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              info.mandatory
                  ? 'Da bi nastavio da koristiš aplikaciju, potrebno je da je ažuriraš.'
                  : 'Preporučujemo da ažuriraš aplikaciju na verziju ${info.latestVersion}.',
            ),
            if (info.notes.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(info.notes, style: Theme.of(ctx).textTheme.bodySmall),
            ],
          ],
        ),
        actions: [
          if (!info.mandatory)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Kasnije'),
            ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _runUpdate(context, info);
            },
            child: const Text('Ažuriraj'),
          ),
        ],
      ),
    ),
  );
}

/// Preuzmi i pokreni instalaciju, uz dijalog sa napretkom preuzimanja.
Future<void> _runUpdate(BuildContext context, UpdateInfo info) async {
  final progress = ValueNotifier<double>(0);

  // Dijalog sa trakom napretka (ne može se zatvoriti dok traje).
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Preuzimanje…'),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, value, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // value == 0 → neodređena traka (dok ne krene preuzimanje).
              LinearProgressIndicator(value: value == 0 ? null : value),
              const SizedBox(height: 12),
              Text(value == 0
                  ? 'Pripremam…'
                  : '${(value * 100).toStringAsFixed(0)}%'),
            ],
          ),
        ),
      ),
    ),
  );

  try {
    await startUpdate(
      url: info.downloadUrl,
      onProgress: (p) => progress.value = p,
    );
    // Android: instalacija je pokrenuta preko sistema → zatvori progres.
    // Windows: aplikacija se ugasi u `startUpdate`, pa dovde i ne stigne.
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop(); // zatvori progres
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Greška pri ažuriranju: $e')),
      );
    }
  } finally {
    progress.dispose();
  }
}
