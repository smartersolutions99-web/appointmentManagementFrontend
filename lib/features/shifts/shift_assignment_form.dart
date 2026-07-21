import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../shared/format.dart';
import '../../shared/widgets.dart';
import '../employees/employees_provider.dart';
import 'shift_assignments_provider.dart';

/// Forma (iskačući prozor) za dodjelu smjene: zaposleni + šablon za IZABRANU
/// sedmicu. Sedmica je fiksna (bira se na ekranu), pa je `weekStartDate` uvijek
/// ispravan ponedjeljak. Vraća [ShiftAssignmentRequest] ili `null` (otkazano).
class ShiftAssignmentForm extends ConsumerStatefulWidget {
  /// Ponedjeljak sedmice za koju dodjeljujemo.
  final DateTime weekStart;

  /// Ako je zadata — uređujemo postojeću dodjelu (prefil zaposlenog/šablona).
  final ShiftAssignmentResponse? existing;

  const ShiftAssignmentForm({
    super.key,
    required this.weekStart,
    this.existing,
  });

  @override
  ConsumerState<ShiftAssignmentForm> createState() =>
      _ShiftAssignmentFormState();
}

class _ShiftAssignmentFormState extends ConsumerState<ShiftAssignmentForm> {
  int? _employeeId;
  int? _templateId;

  @override
  void initState() {
    super.initState();
    _employeeId = widget.existing?.employeeId;
    _templateId = widget.existing?.shiftTemplateId;
  }

  void _save() {
    if (_employeeId == null || _templateId == null) {
      showSnack(context, 'Izaberite zaposlenog i šablon.', isError: true);
      return;
    }
    Navigator.of(context).pop(
      ShiftAssignmentRequest(
        employeeId: _employeeId!,
        shiftTemplateId: _templateId!,
        weekStartDate: ymd(widget.weekStart),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final employeesAsync = ref.watch(employeesProvider);
    final templatesAsync = ref.watch(allShiftTemplatesProvider);
    final weekEnd = widget.weekStart.add(const Duration(days: 6));

    return AlertDialog(
      title: Text(isEdit ? 'Izmjena dodjele' : 'Nova dodjela smjene'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Sedmica (fiksna, samo za informaciju).
            Card(
              margin: EdgeInsets.zero,
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.4),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.calendar_today),
                title: const Text('Sedmica'),
                subtitle: Text(
                  '${Format.date(widget.weekStart)} – ${Format.date(weekEnd)}',
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildEmployeeDropdown(employeesAsync),
            const SizedBox(height: 12),
            _buildTemplateDropdown(templatesAsync),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Otkaži'),
        ),
        FilledButton(onPressed: _save, child: const Text('Sačuvaj')),
      ],
    );
  }

  Widget _buildEmployeeDropdown(AsyncValue<List<EmployeeResponse>> async) {
    return async.when(
      loading: () => const _LoadingField(label: 'Zaposleni'),
      error: (e, _) => _ErrorField(label: 'Zaposleni', message: e.toString()),
      data: (employees) {
        // Zaštita: ako izabrani id nije u listi, ne prosljeđuj ga (Dropdown bi pukao).
        final value =
            employees.any((e) => e.id == _employeeId) ? _employeeId : null;
        return DropdownButtonFormField<int>(
          value: value,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Zaposleni',
            prefixIcon: Icon(Icons.person_outline),
            border: OutlineInputBorder(),
          ),
          items: [
            for (final e in employees)
              DropdownMenuItem(
                value: e.id,
                child: Text(e.name ?? 'Zaposleni ${e.id}'),
              ),
          ],
          onChanged: (v) => setState(() => _employeeId = v),
        );
      },
    );
  }

  Widget _buildTemplateDropdown(AsyncValue<List<ShiftTemplateResponse>> async) {
    return async.when(
      loading: () => const _LoadingField(label: 'Šablon smjene'),
      error: (e, _) =>
          _ErrorField(label: 'Šablon smjene', message: e.toString()),
      data: (templates) {
        if (templates.isEmpty) {
          return const _ErrorField(
            label: 'Šablon smjene',
            message: 'Nema šablona. Prvo napravite šablon smjene.',
          );
        }
        final value =
            templates.any((t) => t.id == _templateId) ? _templateId : null;
        return DropdownButtonFormField<int>(
          value: value,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Šablon smjene',
            prefixIcon: Icon(Icons.calendar_view_week),
            border: OutlineInputBorder(),
          ),
          items: [
            for (final t in templates)
              DropdownMenuItem(
                value: t.id,
                child: Text(t.name ?? 'Šablon ${t.id}'),
              ),
          ],
          onChanged: (v) => setState(() => _templateId = v),
        );
      },
    );
  }
}

/// Polje u stanju učitavanja (dok stiže lista sa servera).
class _LoadingField extends StatelessWidget {
  final String label;
  const _LoadingField({required this.label});

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text('Učitavanje…'),
        ],
      ),
    );
  }
}

/// Polje sa porukom greške/napomene (npr. kad nema šablona).
class _ErrorField extends StatelessWidget {
  final String label;
  final String message;
  const _ErrorField({required this.label, required this.message});

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}

/// Otvara formu dodjele i vraća [ShiftAssignmentRequest] ili `null` (otkazano).
Future<ShiftAssignmentRequest?> showShiftAssignmentForm(
  BuildContext context, {
  required DateTime weekStart,
  ShiftAssignmentResponse? existing,
}) {
  return showDialog<ShiftAssignmentRequest>(
    context: context,
    builder: (_) => ShiftAssignmentForm(weekStart: weekStart, existing: existing),
  );
}
