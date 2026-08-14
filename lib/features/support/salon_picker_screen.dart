import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/exceptions.dart';
import '../../models/models.dart';
import '../../services/providers.dart';
import '../../shared/widgets.dart';
import 'support_provider.dart';

/// „Support mode" salon-picker (SUPER_SUPER_ADMIN). Lista firmi + salona;
/// „Uđi" pokreće impersonaciju i vodi u standardni admin UI tog salona.
class SalonPickerScreen extends ConsumerStatefulWidget {
  const SalonPickerScreen({super.key});

  @override
  ConsumerState<SalonPickerScreen> createState() => _SalonPickerScreenState();
}

class _SalonPickerScreenState extends ConsumerState<SalonPickerScreen> {
  final _search = TextEditingController();
  String _query = '';
  bool _entering = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _enter(int sellingPlaceId) async {
    setState(() => _entering = true);
    final err =
        await ref.read(authControllerProvider).enterSalon(sellingPlaceId);
    if (!mounted) return;
    setState(() => _entering = false);
    if (err != null) {
      showSnack(context, err, isError: true);
    }
    // Uspjeh → router (refreshListenable) automatski preusmjeri na admin UI.
  }

  /// Da li firma/salon odgovara pretrazi (po nazivu firme ili salona/adrese).
  bool _matches(SupportBusiness b) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    if ((b.name ?? '').toLowerCase().contains(q)) return true;
    for (final p in b.sellingPlaces) {
      if ((p.name ?? '').toLowerCase().contains(q) ||
          (p.address ?? '').toLowerCase().contains(q)) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(supportBusinessesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Podrška — izbor salona'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Odjava',
            onPressed: () => ref.read(authControllerProvider).logout(),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Jasna oznaka support moda (drugačija boja).
              Container(
                width: double.infinity,
                color: theme.colorScheme.tertiaryContainer,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.build_circle_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Support mode — izaberi salon u koji ulaziš (uđeš kao '
                        'admin tog salona).',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    hintText: 'Pretraga firme ili salona…',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _search.clear();
                              setState(() => _query = '');
                            },
                          ),
                  ),
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
              ),
              Expanded(
                child: async.when(
                  loading: () => const LoadingView(),
                  error: (e, _) => ErrorView(
                    message: ApiException.from(e).message,
                    onRetry: () => ref.invalidate(supportBusinessesProvider),
                  ),
                  data: (all) {
                    final list = all.where(_matches).toList();
                    if (list.isEmpty) {
                      return const EmptyView(
                        message: 'Nema firmi za prikaz.',
                        icon: Icons.domain_disabled_outlined,
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) => _BusinessCard(
                        business: list[i],
                        onEnter: _enter,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          // Prekrivač dok ulazimo u salon.
          if (_entering)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x66000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}

class _BusinessCard extends StatelessWidget {
  final SupportBusiness business;
  final void Function(int sellingPlaceId) onEnter;

  const _BusinessCard({required this.business, required this.onEnter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final places = business.sellingPlaces;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Zaglavlje firme (naziv + status).
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
          child: Row(
            children: [
              Icon(Icons.domain_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  business.name ?? 'Firma ${business.id}',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              if ((business.status ?? '').isNotEmpty)
                Chip(
                  label: Text(business.status!),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ],
          ),
        ),
        // Saloni firme — svaki kao svoja kartica.
        if (places.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text('Nema salona.', style: theme.textTheme.bodySmall),
          )
        else
          for (final p in places)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _SalonCard(place: p, onEnter: onEnter),
            ),
      ],
    );
  }
}

/// Jedna kartica salona: naziv + adresa, pa dugme „Uđi u salon" PREKO CIJELE
/// širine u zasebnom redu — tako naziv uvijek ima punu širinu i ne lomi se.
class _SalonCard extends StatelessWidget {
  final SupportSellingPlace place;
  final void Function(int sellingPlaceId) onEnter;

  const _SalonCard({required this.place, required this.onEnter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final address = (place.address ?? '').trim();

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.store_mall_directory_outlined,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        place.name ?? 'Salon ${place.id}',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      if (address.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          address,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.hintColor),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: place.id == null ? null : () => onEnter(place.id!),
              icon: const Icon(Icons.login, size: 18),
              label: const Text('Uđi u salon'),
            ),
          ],
        ),
      ),
    );
  }
}
