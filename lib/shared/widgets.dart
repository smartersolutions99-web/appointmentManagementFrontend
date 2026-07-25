import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'scissors_loader.dart';

/// Skup malih, ponovo upotrebljivih widgeta i pomoćnih funkcija
/// koje koristimo na više ekrana (da ne ponavljamo kod).

/// Prikazuje stanje učitavanja (slatka animacija makaza — brend salona).
class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: ScissorsLoader());
  }
}

/// Prikazuje grešku sa dugmetom „Pokušaj ponovo“.
class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const ErrorView({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: onRetry,
                child: const Text('Pokušaj ponovo'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Prikazuje poruku kada nema podataka (prazna lista).
class EmptyView extends StatelessWidget {
  final String message;
  final IconData icon;

  const EmptyView({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Theme.of(context).disabledColor),
          const SizedBox(height: 12),
          Text(message, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}

/// Univerzalni prikaz za Riverpod `AsyncValue` (učitavanje/greška/podaci).
///
/// Umjesto da na svakom ekranu pišemo `when(loading:..., error:..., data:...)`,
/// koristimo ovaj widget i prosljeđujemo samo kako da nacrtamo podatke.
class AsyncValueView<T> extends StatelessWidget {
  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;

  const AsyncValueView({
    super.key,
    required this.value,
    required this.data,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    // Ako VEĆ imamo podatke, prikazujemo ih čak i dok se u pozadini osvježavaju
    // (npr. poslije zakazivanja ili promjene statusa). Time izbjegavamo „bljesak"
    // — trenutak kad se cijeli ekran zamijeni vrtićem pa se vrati. Vrtić i grešku
    // pokazujemo samo pri PRVOM učitavanju (kad još nemamo ništa da prikažemo).
    if (value.hasValue) {
      return data(value.requireValue);
    }
    if (value.hasError) {
      return ErrorView(
        message: value.error.toString(),
        onRetry: onRetry,
      );
    }
    return const LoadingView();
  }
}

/// Prikazuje kratku poruku na dnu ekrana (snackbar).
void showSnack(BuildContext context, String message, {bool isError = false}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.redAccent : null,
    ),
  );
}

/// Pita korisnika za potvrdu (npr. prije brisanja). Vraća true/false.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmText = 'Potvrdi',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Otkaži'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmText),
        ),
      ],
    ),
  );
  return result ?? false;
}
