import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/exceptions.dart';
import '../../models/models.dart';
import '../../services/providers.dart';
import '../../shared/format.dart';
import '../../shared/widgets.dart';
import 'services_provider.dart';

/// Ekran sa listom usluga (CRUD). Forma za unos je jednostavna, pa je držimo
/// u istom fajlu (funkcija `_showServiceForm`).
class ServicesScreen extends ConsumerWidget {
  const ServicesScreen({super.key});

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref, {
    ServiceEntityResponse? existing,
  }) async {
    final request = await _showServiceForm(context, existing: existing);
    if (request == null) return;

    final api = ref.read(apiServiceProvider);
    try {
      if (existing == null) {
        await api.createService(request);
      } else {
        await api.updateService(existing.id!, request);
      }
      ref.invalidate(servicesProvider);
      if (context.mounted) showSnack(context, 'Sačuvano.');
    } catch (e) {
      if (context.mounted) {
        showSnack(context, ApiException.from(e).message, isError: true);
      }
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    ServiceEntityResponse service,
  ) async {
    final ok = await confirmDialog(
      context,
      title: 'Brisanje usluge',
      message: 'Obrisati „${service.name}“?',
      confirmText: 'Obriši',
    );
    if (!ok) return;
    try {
      await ref.read(apiServiceProvider).deleteService(service.id!);
      ref.invalidate(servicesProvider);
      if (context.mounted) showSnack(context, 'Usluga obrisana.');
    } catch (e) {
      if (context.mounted) {
        showSnack(context, ApiException.from(e).message, isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servicesAsync = ref.watch(servicesProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nova usluga'),
      ),
      body: AsyncValueView<List<ServiceEntityResponse>>(
        value: servicesAsync,
        onRetry: () => ref.invalidate(servicesProvider),
        data: (services) {
          if (services.isEmpty) {
            return const EmptyView(message: 'Nema usluga.');
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            itemCount: services.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final s = services[index];
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.content_cut)),
                  title: Text(s.name ?? '—'),
                  subtitle: s.description == null || s.description!.isEmpty
                      ? null
                      : Text(s.description!),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        Format.money(s.basicPrice),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (v) => v == 'edit'
                            ? _openForm(context, ref, existing: s)
                            : _delete(context, ref, s),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Izmijeni')),
                          PopupMenuItem(value: 'delete', child: Text('Obriši')),
                        ],
                      ),
                    ],
                  ),
                  onTap: () => _openForm(context, ref, existing: s),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Jednostavna forma za uslugu (naziv, cijena, opis).
Future<ServiceEntityRequest?> _showServiceForm(
  BuildContext context, {
  ServiceEntityResponse? existing,
}) {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController(text: existing?.name ?? '');
  final price = TextEditingController(
    text: existing?.basicPrice?.toString() ?? '',
  );
  final description = TextEditingController(text: existing?.description ?? '');

  return showDialog<ServiceEntityRequest>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(existing == null ? 'Nova usluga' : 'Izmijeni uslugu'),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Naziv'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Obavezno polje' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Osnovna cijena (€)'),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Obavezno polje';
                if (double.tryParse(v.replaceAll(',', '.')) == null) {
                  return 'Unesite ispravan broj';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: description,
              decoration: const InputDecoration(labelText: 'Opis (opciono)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Otkaži'),
        ),
        FilledButton(
          onPressed: () {
            if (!formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              ServiceEntityRequest(
                name: name.text.trim(),
                basicPrice: double.parse(price.text.replaceAll(',', '.')),
                description: description.text.trim().isEmpty
                    ? null
                    : description.text.trim(),
              ),
            );
          },
          child: const Text('Sačuvaj'),
        ),
      ],
    ),
  );
}
