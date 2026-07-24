import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../services/providers.dart';

/// Zaključava osjetljive stranice (Izvještaji, Zaposleni): pri svakom ulasku
/// traži da korisnik PONOVO unese lozinku. Na tačnu lozinku prikaže [child];
/// na otkazivanje vraća na početnu.
class PasswordGate extends ConsumerStatefulWidget {
  final Widget child;
  final String title; // naziv stranice (za poruku)

  const PasswordGate({super.key, required this.child, required this.title});

  @override
  ConsumerState<PasswordGate> createState() => _PasswordGateState();
}

class _PasswordGateState extends ConsumerState<PasswordGate> {
  bool _unlocked = false;
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    // Odmah po prvom kadru zatraži lozinku.
    WidgetsBinding.instance.addPostFrameCallback((_) => _prompt());
  }

  Future<void> _prompt() async {
    if (_unlocked || _asking) return;
    _asking = true;
    final ok = await _askPassword();
    _asking = false;
    if (!mounted) return;
    if (ok) {
      setState(() => _unlocked = true);
    } else {
      context.go('/'); // otkazano → nazad na početnu
    }
  }

  Future<bool> _askPassword() async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        String? error;
        bool loading = false;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            Future<void> submit() async {
              final pass = controller.text;
              if (pass.isEmpty) {
                setLocal(() => error = 'Unesite lozinku');
                return;
              }
              setLocal(() {
                loading = true;
                error = null;
              });
              final ok =
                  await ref.read(authControllerProvider).verifyPassword(pass);
              if (!ctx.mounted) return;
              if (ok) {
                Navigator.pop(ctx, true);
              } else {
                setLocal(() {
                  loading = false;
                  error = 'Pogrešna lozinka';
                });
              }
            }

            return AlertDialog(
              title: Text('Zaključano — ${widget.title}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Unesite lozinku da nastavite.'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    obscureText: true,
                    autofocus: true,
                    enabled: !loading,
                    onSubmitted: (_) => submit(),
                    decoration: InputDecoration(
                      labelText: 'Lozinka',
                      errorText: error,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: loading ? null : () => Navigator.pop(ctx, false),
                  child: const Text('Otkaži'),
                ),
                FilledButton(
                  onPressed: loading ? null : submit,
                  child: loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Potvrdi'),
                ),
              ],
            );
          },
        );
      },
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) return widget.child;
    // Zaključan prikaz (dok se lozinka ne potvrdi).
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline, size: 48),
          const SizedBox(height: 12),
          Text('${widget.title} je zaključano',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _prompt,
            icon: const Icon(Icons.lock_open_outlined),
            label: const Text('Unesi lozinku'),
          ),
        ],
      ),
    );
  }
}
