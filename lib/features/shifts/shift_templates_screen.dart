import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../shared/widgets.dart';
import 'shift_template_form.dart';
import 'shift_templates_provider.dart';

/// Ekran sa listom šablona smjena (ADMIN): pretraga, paginacija (beskonačni
/// skrol), dodavanje. Tap na red otvara izmjenu (gdje je i brisanje).
class ShiftTemplatesScreen extends ConsumerStatefulWidget {
  const ShiftTemplatesScreen({super.key});

  @override
  ConsumerState<ShiftTemplatesScreen> createState() =>
      _ShiftTemplatesScreenState();
}

class _ShiftTemplatesScreenState extends ConsumerState<ShiftTemplatesScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();

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

  void _onScroll() {
    final p = _scrollController.position;
    if (p.pixels >= p.maxScrollExtent - 200) {
      ref.read(shiftTemplatesControllerProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(shiftTemplatesControllerProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showShiftTemplateForm(context),
        icon: const Icon(Icons.add),
        label: const Text('Novi šablon'),
      ),
      body: Column(
        children: [
          // Pretraga (debounce je u kontroleru).
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Pretraga po nazivu…',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          ref
                              .read(shiftTemplatesControllerProvider.notifier)
                              .setSearch('');
                          setState(() {});
                        },
                      ),
              ),
              onChanged: (v) {
                ref
                    .read(shiftTemplatesControllerProvider.notifier)
                    .setSearch(v);
                setState(() {}); // da se osvježi „clear“ ikonica
              },
            ),
          ),
          Expanded(child: _buildBody(state)),
        ],
      ),
    );
  }

  Widget _buildBody(ShiftTemplatesState state) {
    if (state.isLoading) return const LoadingView();

    if (state.error != null && state.items.isEmpty) {
      return ErrorView(
        message: state.error!,
        onRetry: () =>
            ref.read(shiftTemplatesControllerProvider.notifier).loadFirstPage(),
      );
    }

    if (state.items.isEmpty) {
      return const EmptyView(
        message: 'Nema šablona smjena.',
        icon: Icons.calendar_view_week_outlined,
      );
    }

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(shiftTemplatesControllerProvider.notifier).loadFirstPage(),
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
        itemCount: state.items.length + (state.hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index >= state.items.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return _buildCard(state.items[index]);
        },
      ),
    );
  }

  Widget _buildCard(ShiftTemplateResponse template) {
    final note = template.note?.trim();
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.calendar_view_week)),
        title: Text(template.name ?? 'Bez naziva'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (note != null && note.isNotEmpty)
              Text(note, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(
              _daysSummary(template),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        isThreeLine: note != null && note.isNotEmpty,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showShiftTemplateForm(context, existing: template),
      ),
    );
  }

  /// Kratak pregled radnih dana, npr. "Pon 09:00–17:00, Sub 10:00–16:00".
  String _daysSummary(ShiftTemplateResponse template) {
    if (template.days.isEmpty) return 'Nema radnih dana';
    // Poredaj po danu (Pon→Ned) da prikaz bude uredan.
    final sorted = [...template.days]
      ..sort((a, b) => a.dayOfWeek.index.compareTo(b.dayOfWeek.index));
    return sorted
        .map((d) =>
            '${d.dayOfWeek.shortLabel} ${_hhmm(d.startTime)}–${_hhmm(d.endTime)}')
        .join(', ');
  }

  /// "HH:mm:ss" → "HH:mm" (ili "—" ako fali).
  String _hhmm(String? t) {
    if (t == null || t.length < 5) return '—';
    return t.substring(0, 5);
  }
}
