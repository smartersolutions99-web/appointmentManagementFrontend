import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/exceptions.dart';
import '../../models/models.dart';
import '../../services/providers.dart';
import '../../shared/widgets.dart';
import 'employee_form.dart';
import 'employees_provider.dart';

/// Ekran sa listom zaposlenih (dodavanje, izmjena, brisanje).
class EmployeesScreen extends ConsumerWidget {
  const EmployeesScreen({super.key});

  /// Otvara formu i šalje zahtjev (kreiranje ili izmjena).
  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref, {
    EmployeeResponse? existing,
  }) async {
    // Padajuće liste u formi traže uloge i prodajna mjesta — učitaj ih.
    final roles = await ref.read(rolesProvider.future);
    final places = await ref.read(sellingPlacesProvider.future);
    if (!context.mounted) return;

    final request = await showDialog<EmployeeRequest>(
      context: context,
      builder: (_) => EmployeeForm(
        existing: existing,
        roles: roles,
        sellingPlaces: places,
      ),
    );
    if (request == null) return;

    final api = ref.read(apiServiceProvider);
    try {
      if (existing == null) {
        await api.createEmployee(request);
      } else {
        await api.updateEmployee(existing.id!, request);
      }
      ref.invalidate(employeesProvider); // osvježi listu
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
    EmployeeResponse employee,
  ) async {
    final ok = await confirmDialog(
      context,
      title: 'Brisanje zaposlenog',
      message: 'Obrisati „${employee.name}“?',
      confirmText: 'Obriši',
    );
    if (!ok) return;

    try {
      await ref.read(apiServiceProvider).deleteEmployee(employee.id!);
      ref.invalidate(employeesProvider);
      if (context.mounted) showSnack(context, 'Zaposleni obrisan.');
    } catch (e) {
      if (context.mounted) {
        showSnack(context, ApiException.from(e).message, isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // „Slušamo“ listu zaposlenih (AsyncValue: loading/error/data).
    final employeesAsync = ref.watch(employeesProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Novi zaposleni'),
      ),
      body: AsyncValueView<List<EmployeeResponse>>(
        value: employeesAsync,
        onRetry: () => ref.invalidate(employeesProvider),
        data: (employees) {
          if (employees.isEmpty) {
            return const EmptyView(message: 'Nema zaposlenih.');
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            itemCount: employees.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final e = employees[index];
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(e.name ?? '—'),
                  subtitle: Text(
                    [e.email, e.phoneNumber]
                        .where((s) => s != null && s.isNotEmpty)
                        .join(' • '),
                  ),
                  onTap: () => _openForm(context, ref, existing: e),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) => v == 'edit'
                        ? _openForm(context, ref, existing: e)
                        : _delete(context, ref, e),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Izmijeni')),
                      PopupMenuItem(value: 'delete', child: Text('Obriši')),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
