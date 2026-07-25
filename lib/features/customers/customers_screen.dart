import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/exceptions.dart';
import '../../models/models.dart';
import '../../shared/widgets.dart';
import 'customer_form.dart';
import 'customers_provider.dart';

/// Ekran sa listom klijenata. Podržava paginaciju (beskonačni skrol),
/// dodavanje, izmjenu i brisanje.
class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  // Kontroler skrola — pratimo kada korisnik dođe blizu dna liste.
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Kada se približimo dnu (200px), traži sljedeću stranicu.
  void _onScroll() {
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      ref.read(customersControllerProvider.notifier).loadMore();
    }
  }

  /// Otvara formu za dodavanje ili izmjenu i šalje zahtjev serveru.
  Future<void> _openForm({CustomerResponse? existing}) async {
    final request = await showCustomerForm(context, existing: existing);
    if (request == null) return; // korisnik otkazao

    final controller = ref.read(customersControllerProvider.notifier);
    try {
      if (existing == null) {
        await controller.create(request);
      } else {
        await controller.update(existing.id!, request);
      }
      if (mounted) showSnack(context, 'Sačuvano.');
    } catch (e) {
      if (mounted) showSnack(context, ApiException.from(e).message, isError: true);
    }
  }

  /// Potvrda + brisanje klijenta.
  Future<void> _delete(CustomerResponse customer) async {
    final ok = await confirmDialog(
      context,
      title: 'Brisanje klijenta',
      message: 'Da li ste sigurni da želite obrisati „${customer.name}“?',
      confirmText: 'Obriši',
    );
    if (!ok) return;

    try {
      await ref.read(customersControllerProvider.notifier).delete(customer.id!);
      if (mounted) showSnack(context, 'Klijent obrisan.');
    } catch (e) {
      if (mounted) showSnack(context, ApiException.from(e).message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(customersControllerProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Novi klijent'),
      ),
      body: _buildBody(state),
    );
  }

  Widget _buildBody(CustomersState state) {
    // Prvo učitavanje.
    if (state.isLoading) return const LoadingView();

    // Greška pri prvom učitavanju (lista je još prazna).
    if (state.error != null && state.items.isEmpty) {
      return ErrorView(
        message: state.error!,
        onRetry: () => ref.read(customersControllerProvider.notifier).loadFirstPage(),
      );
    }

    // Nema klijenata.
    if (state.items.isEmpty) {
      return const EmptyView(
        message: 'Nema klijenata. Dodajte prvog.',
        icon: Icons.people_outline,
      );
    }

    // Lista klijenata sa „povuci da osvježiš“.
    return RefreshIndicator(
      onRefresh: () =>
          ref.read(customersControllerProvider.notifier).loadFirstPage(),
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
        // +1 red na kraju za indikator učitavanja sljedeće stranice.
        itemCount: state.items.length + (state.hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          // Posljednji red = indikator „učitavam još“.
          if (index >= state.items.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: LoadingView(),
            );
          }

          final customer = state.items[index];
          return _CustomerTile(
            customer: customer,
            onEdit: () => _openForm(existing: customer),
            onDelete: () => _delete(customer),
          );
        },
      ),
    );
  }
}

/// Jedna kartica klijenta u listi.
class _CustomerTile extends StatelessWidget {
  final CustomerResponse customer;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CustomerTile({
    required this.customer,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          // Prvo slovo imena kao avatar.
          child: Text(
            (customer.name?.isNotEmpty ?? false)
                ? customer.name![0].toUpperCase()
                : '?',
          ),
        ),
        title: Text(customer.name ?? 'Bez imena'),
        subtitle: Text(customer.contactValue ?? '—'),
        onTap: onEdit,
        // Meni sa tri tačkice (izmjena/brisanje).
        trailing: PopupMenuButton<String>(
          onSelected: (value) => value == 'edit' ? onEdit() : onDelete(),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('Izmijeni')),
            PopupMenuItem(value: 'delete', child: Text('Obriši')),
          ],
        ),
      ),
    );
  }
}
