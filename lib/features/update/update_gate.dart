import 'package:flutter/material.dart';

import '../../services/update_service.dart';

/// Provjeravamo nadogradnju samo JEDNOM po pokretanju aplikacije.
/// (AppShell se pregrađuje pri svakoj navigaciji, pa čuvamo zastavicu ovdje da
/// se dijalog ne bi ponavljao.)
bool _checkedThisSession = false;

/// „Tihi" omotač koji, prvi put nakon prijave, provjeri da li postoji nova
/// verzija i po potrebi prikaže dijalog. Ne mijenja izgled ekrana — samo
/// prosljeđuje `child` dalje. Postavlja se unutar AppShell-a (poslije prijave).
class UpdateGate extends StatefulWidget {
  final Widget child;
  const UpdateGate({super.key, required this.child});

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  @override
  void initState() {
    super.initState();
    if (_checkedThisSession) return;
    _checkedThisSession = true;
    // Poslije prvog kadra (kad ekran postoji) — provjeri u pozadini.
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    final info = await checkForUpdate();
    if (info == null || !mounted) return;
    await _showUpdateDialog(info);
  }

  /// Prikaži dijalog „dostupna je nova verzija".
  ///
  /// - Obavezna nadogradnja: dijalog se ne može zatvoriti (nema „Kasnije",
  ///   ni zatvaranje dodirom pored, ni „nazad" dugmetom).
  /// - Opciona: korisnik može izabrati „Kasnije" i nastaviti da radi.
  Future<void> _showUpdateDialog(UpdateInfo info) {
    return showDialog<void>(
      context: context,
      barrierDismissible: !info.mandatory,
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
                Text(
                  info.notes,
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ],
            ],
          ),
          actions: [
            if (!info.mandatory)
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Kasnije'),
              ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                _runUpdate(info);
              },
              icon: const Icon(Icons.download),
              label: const Text('Ažuriraj'),
            ),
          ],
        ),
      ),
    );
  }

  /// Preuzmi i pokreni instalaciju, uz dijalog sa napretkom preuzimanja.
  Future<void> _runUpdate(UpdateInfo info) async {
    final progress = ValueNotifier<double>(0);

    // Dijalog sa trakom napretka (ne može se zatvoriti dok traje).
    showDialog<void>(
      context: context,
      barrierDismissible: false,
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
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // zatvori progres
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Greška pri ažuriranju: $e')),
        );
      }
    } finally {
      progress.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
