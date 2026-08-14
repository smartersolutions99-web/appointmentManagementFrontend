import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/exceptions.dart';
import '../../models/models.dart';
import '../../shared/format.dart';
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
  final _searchController = TextEditingController();
  String _query = ''; // tekuća pretraga (po imenu ili telefonu)

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
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
      ref.invalidate(allCustomersProvider); // osvježi i pretragu
      if (mounted) showSnack(context, 'Sačuvano.');
    } catch (e) {
      if (mounted) showSnack(context, ApiException.from(e).message, isError: true);
    }
  }

  /// Otvara detalj klijenta (statistika + alert za česte no-show) u „sheet"-u.
  void _showDetail(CustomerResponse customer) {
    if (customer.id == null) {
      _openForm(existing: customer); // bez id-a nema statistike — otvori izmjenu
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CustomerDetailSheet(
        customer: customer,
        onEdit: () {
          Navigator.pop(context); // zatvori sheet
          _openForm(existing: customer);
        },
      ),
    );
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
      ref.invalidate(allCustomersProvider); // osvježi i pretragu
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
      body: Column(
        children: [
          // Pretraga (po imenu ili telefonu). Prazno polje → obična lista.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Pretraga po imenu ili telefonu…',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          Expanded(
            child: _query.isEmpty ? _buildBody(state) : _buildSearchResults(),
          ),
        ],
      ),
    );
  }

  /// Rezultati pretrage — filtriramo LOKALNO kroz sve klijente (po imenu/telefonu).
  Widget _buildSearchResults() {
    final async = ref.watch(allCustomersProvider);
    return async.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(
        message: ApiException.from(e).message,
        onRetry: () => ref.invalidate(allCustomersProvider),
      ),
      data: (all) {
        final q = _query.toLowerCase();
        final results = all
            .where((c) =>
                (c.name ?? '').toLowerCase().contains(q) ||
                (c.contactValue ?? '').toLowerCase().contains(q))
            .toList();
        if (results.isEmpty) {
          return const EmptyView(
            message: 'Nema rezultata za pretragu.',
            icon: Icons.search_off,
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
          itemCount: results.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final customer = results[index];
            return _CustomerTile(
              customer: customer,
              onTap: () => _showDetail(customer),
              onEdit: () => _openForm(existing: customer),
              onDelete: () => _delete(customer),
            );
          },
        );
      },
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
            onTap: () => _showDetail(customer),
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
  final VoidCallback onTap; // otvara detalj (statistika)
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CustomerTile({
    required this.customer,
    required this.onTap,
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
        onTap: onTap,
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

/// Detalj klijenta (u „bottom sheet"-u): statistika sa servera + alert za
/// česte no-show. Otvara se klikom na klijenta u listi.
class _CustomerDetailSheet extends ConsumerWidget {
  final CustomerResponse customer;
  final VoidCallback onEdit;

  const _CustomerDetailSheet({required this.customer, required this.onEdit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final statsAsync = ref.watch(customerStatsProvider(customer.id!));

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Zaglavlje: avatar + ime + kontakt.
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    child: Text(
                      (customer.name?.isNotEmpty ?? false)
                          ? customer.name![0].toUpperCase()
                          : '?',
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(customer.name ?? 'Bez imena',
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        if ((customer.contactValue ?? '').isNotEmpty)
                          Text(customer.contactValue!,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.hintColor)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              statsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => ErrorView(
                  message: ApiException.from(e).message,
                  onRetry: () =>
                      ref.invalidate(customerStatsProvider(customer.id!)),
                ),
                data: (stats) => _statsBody(context, stats),
              ),

              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      label: const Text('Zatvori'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Izmijeni'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statsBody(BuildContext context, CustomerStatsResponse s) {
    final theme = Theme.of(context);
    final frequentNoShow = s.noShow >= kFrequentNoShowThreshold;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Upozorenje za česte no-show.
        if (frequentNoShow) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: theme.colorScheme.error),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Čest no-show — nije se pojavio ${s.noShow} puta. Razmisli o '
                    'potvrdi termina ili avansu.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Glavne cifre: potrošeno + ukupno termina.
        Card(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _bigStat(theme, 'Potrošeno', Format.money(s.totalSpent)),
                _bigStat(theme, 'Ukupno termina', '${s.totalAppointments}'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Razbijeno po statusu.
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _statChip(theme, 'Zakazani', s.scheduled, Colors.blue),
            _statChip(theme, 'Završeni', s.completed, Colors.green),
            _statChip(theme, 'Otkazani', s.cancelled, Colors.red),
            _statChip(theme, 'Nije se pojavio', s.noShow, Colors.orange),
          ],
        ),
      ],
    );
  }

  Widget _bigStat(ThemeData theme, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(value,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _statChip(ThemeData theme, String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$value',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(width: 6),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
