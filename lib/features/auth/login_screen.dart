import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/providers.dart';
import '../../shared/widgets.dart';

/// Ekran za prijavu korisnika.
///
/// `ConsumerStatefulWidget` koristimo jer imamo lokalno stanje (tekst polja,
/// da li je lozinka skrivena, da li se trenutno učitava) i pristup Riverpodu.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  // Kontroleri čuvaju tekst koji korisnik unese.
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  // Ključ forme — omogućava validaciju svih polja odjednom.
  final _formKey = GlobalKey<FormState>();

  bool _obscurePassword = true; // Da li je lozinka skrivena.
  bool _loading = false; // Da li je prijava u toku.

  @override
  void dispose() {
    // Obavezno oslobodi kontrolere kada ekran nestane (sprječava curenje memorije).
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Pokušaj prijave kada korisnik klikne dugme.
  Future<void> _submit() async {
    // Prvo provjeri da su polja ispravno popunjena.
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    // Pozovi prijavu. Vraća poruku greške ili null (uspjeh).
    final error = await ref.read(authControllerProvider).login(
          _usernameController.text.trim(),
          _passwordController.text,
        );

    if (!mounted) return; // Ako je ekran u međuvremenu nestao, ne diraj UI.
    setState(() => _loading = false);

    if (error != null) {
      showSnack(context, error, isError: true);
    }
    // Ako je uspjeh, router automatski prebacuje na početnu stranicu.
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            // Ograničavamo širinu kako bi lijepo izgledalo i na velikom ekranu.
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo / ikonica.
                  Icon(Icons.cut, size: 64, color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Salon Menadžment',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Prijavite se da nastavite',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.hintColor),
                  ),
                  const SizedBox(height: 32),

                  // Polje za korisničko ime.
                  TextFormField(
                    controller: _usernameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Korisničko ime',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                            ? 'Unesite korisničko ime'
                            : null,
                  ),
                  const SizedBox(height: 16),

                  // Polje za lozinku (sa dugmetom za prikaz/skrivanje).
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Lozinka',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: (value) => (value == null || value.isEmpty)
                        ? 'Unesite lozinku'
                        : null,
                  ),
                  const SizedBox(height: 24),

                  // Dugme za prijavu (prikazuje spinner dok traje).
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Prijavi se'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
