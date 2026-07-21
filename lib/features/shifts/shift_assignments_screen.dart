import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/exceptions.dart';
import '../../models/models.dart';
import '../../shared/format.dart';
import '../../shared/widgets.dart';
import 'shift_assignment_form.dart';
import 'shift_assignments_provider.dart';

/// Ekran za dodjelu smjena (ADMIN): bira se sedmica, pa se za tu sedmicu vidi
/// ko prati koji šablon. Dodavanje/izmjena/brisanje dodjela.
class ShiftAssignmentsScreen extends ConsumerStatefulWidget {
  const ShiftAssignmentsScreen({super.key});

  @override
  ConsumerState<ShiftAssignmentsScreen> createState() =>
      _ShiftAssignmentsScreenState();
}

class _ShiftAssignmentsScreenState
    extends ConsumerState<ShiftAssignmentsScreen> {
  ShiftAssignmentsController get _ctrl =>
      ref.read(shiftAssignmentsControllerProvider.notifier);

  /// Otvori kalendar i skoči na sedmicu izabranog datuma.
  Future<void> _pickWeek(DateTime current) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) _ctrl.setWeekFromDate(picked);
  }

  Future<void> _add(DateTime weekStart) async {
    final request =
        await showShiftAssignmentForm(context, weekStart: weekStart);
    if (request == null) return;
    try {
      await _ctrl.create(request);
      if (mounted) showSnack(context, 'Dodjela sačuvana.');
    } catch (e) {
      if (mounted) {
        showSnack(context, ApiException.from(e).message, isError: true);
      }
    }
  }

  Future<void> _edit(ShiftAssignmentResponse a, DateTime weekStart) async {
    final request = await showShiftAssignmentForm(
      context,
      weekStart: weekStart,
      existing: a,
    );
    if (request == null) return;
    try {
      await _ctrl.update(a.id!, request);
      if (mounted) showSnack(context, 'Dodjela izmijenjena.');
    } catch (e) {
      if (mounted) {
        showSnack(context, ApiException.from(e).message, isError: true);
      }
    }
  }

  Future<void> _delete(ShiftAssignmentResponse a) async {
    final ok = await confirmDialog(
      context,
      title: 'Obriši dodjelu',
      message:
          'Ukloniti dodjelu za „${a.employeeName ?? 'zaposlenog'}“ ove sedmice?',
      confirmText: 'Obriši',
    );
    if (!ok) return;
    try {
      await _ctrl.delete(a.id!);
      if (mounted) showSnack(context, 'Dodjela obrisana.');
    } catch (e) {
      if (mounted) {
        showSnack(context, ApiException.from(e).message, isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(shiftAssignmentsControllerProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(state.weekStart),
        icon: const Icon(Icons.add),
        label: const Text('Nova dodjela'),
      ),
      body: Column(
        children: [
          _buildWeekBar(state.weekStart),
          Expanded(child: _buildBody(state)),
        ],
      ),
    );
  }

  /// Gornja traka: prethodna/sljedeća sedmica + raspon (klik otvara kalendar).
  Widget _buildWeekBar(DateTime weekStart) {
    final weekEnd = weekStart.add(const Duration(days: 6));
    return Material(
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Prethodna sedmica',
              onPressed: () => _ctrl.shiftWeek(-1),
            ),
            Expanded(
              child: TextButton.icon(
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text('${Format.date(weekStart)} – ${Format.date(weekEnd)}'),
                onPressed: () => _pickWeek(weekStart),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Sljedeća sedmica',
              onPressed: () => _ctrl.shiftWeek(1),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ShiftAssignmentsState state) {
    if (state.isLoading) return const LoadingView();

    if (state.error != null && state.items.isEmpty) {
      return ErrorView(message: state.error!, onRetry: _ctrl.load);
    }

    if (state.items.isEmpty) {
      return const EmptyView(
        message: 'Nema dodjela za ovu sedmicu.',
        icon: Icons.assignment_ind_outlined,
      );
    }

    return RefreshIndicator(
      onRefresh: _ctrl.load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
        itemCount: state.items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final a = state.items[index];
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                child: Text(
                  (a.employeeName?.isNotEmpty ?? false)
                      ? a.employeeName![0].toUpperCase()
                      : '?',
                ),
              ),
              title: Text(a.employeeName ?? 'Zaposleni ${a.employeeId}'),
              subtitle: Text(a.shiftTemplateName ?? 'Šablon ${a.shiftTemplateId}'),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Obriši',
                onPressed: () => _delete(a),
              ),
              onTap: () => _edit(a, state.weekStart),
            ),
          );
        },
      ),
    );
  }
}
