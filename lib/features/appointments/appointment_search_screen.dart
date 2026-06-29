import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/format.dart';
import '../../shared/widgets.dart';
import 'barber_colors.dart';
import 'day_schedule_provider.dart';

/// Ekran za pretragu termina po imenu klijenta ili broju telefona.
///
/// Korisnik ukuca dio imena ili telefona; prikazujemo sve termine (narednih
/// 90 dana) koji se poklapaju, sa datumom, vremenom, barberom i klijentom.
class AppointmentSearchScreen extends ConsumerStatefulWidget {
  const AppointmentSearchScreen({super.key});

  @override
  ConsumerState<AppointmentSearchScreen> createState() =>
      _AppointmentSearchScreenState();
}

class _AppointmentSearchScreenState
    extends ConsumerState<AppointmentSearchScreen> {
  final _controller = TextEditingController();
  // Tekst po kojem stvarno tražimo (mijenja se kad korisnik potvrdi pretragu).
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _runSearch() {
    setState(() => _query = _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pretraga termina')),
      body: Column(
        children: [
          // Polje za unos imena ili telefona.
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _runSearch(),
              decoration: InputDecoration(
                labelText: 'Ime klijenta ili telefon',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  tooltip: 'Pretraži',
                  onPressed: _runSearch,
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  Widget _buildResults() {
    // Dok ništa nije uneseno — uputstvo.
    if (_query.isEmpty) {
      return const EmptyView(
        message: 'Unesite ime ili telefon i pritisnite Enter.',
        icon: Icons.person_search_outlined,
      );
    }

    final resultsAsync = ref.watch(appointmentSearchProvider(_query));
    return AsyncValueView<List<AgendaItem>>(
      value: resultsAsync,
      onRetry: () => ref.invalidate(appointmentSearchProvider(_query)),
      data: (items) {
        if (items.isEmpty) {
          return const EmptyView(
            message: 'Nema zakazanih termina za tu pretragu.',
            icon: Icons.event_busy_outlined,
          );
        }
        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) => _resultTile(items[i]),
        );
      },
    );
  }

  Widget _resultTile(AgendaItem it) {
    final color = barberColor(it.employeeId);
    final client = [it.customerName, it.customerPhone]
        .where((s) => s != null && s.isNotEmpty)
        .join('  ·  ');

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color,
        radius: 6,
      ),
      title: Text(client.isEmpty ? 'Klijent' : client),
      subtitle: Text(
        '${Format.dateTime(it.start)}'
        '${it.barberName != null ? '  ·  ${it.barberName}' : ''}',
      ),
    );
  }
}
