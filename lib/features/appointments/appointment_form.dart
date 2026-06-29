import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../shared/format.dart';

/// Forma za kreiranje novog termina.
///
/// Vraća [AppointmentRequest] ili `null` ako je otkazano. Zbog biranja datuma
/// i vremena koristimo `StatefulBuilder` da dijalog može osvježavati prikaz.
Future<AppointmentRequest?> showAppointmentForm(
  BuildContext context, {
  required bool isAdmin,
  int? currentEmployeeId,
  required List<EmployeeResponse> employees,
}) {
  final formKey = GlobalKey<FormState>();
  final customerName = TextEditingController();
  final phone = TextEditingController();
  final duration = TextEditingController(text: '30'); // podrazumijevano 30 min
  final price = TextEditingController();
  final note = TextEditingController();

  // Admin bira zaposlenog iz liste; običnom zaposlenom je „zakucan“ njegov nalog.
  int? employeeId = isAdmin ? null : currentEmployeeId;
  // Početno vrijeme: sljedeći puni sat.
  DateTime startTime = DateTime.now().add(const Duration(hours: 1));
  startTime = DateTime(startTime.year, startTime.month, startTime.day, startTime.hour);

  return showDialog<AppointmentRequest>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        // Otvara biranje datuma pa vremena i ažurira `startTime`.
        Future<void> pickDateTime() async {
          final date = await showDatePicker(
            context: context,
            initialDate: startTime,
            firstDate: DateTime.now().subtract(const Duration(days: 1)),
            lastDate: DateTime.now().add(const Duration(days: 365)),
          );
          if (date == null || !context.mounted) return;

          final time = await showTimePicker(
            context: context,
            initialTime: TimeOfDay.fromDateTime(startTime),
          );
          if (time == null) return;

          setState(() {
            startTime = DateTime(
              date.year,
              date.month,
              date.day,
              time.hour,
              time.minute,
            );
          });
        }

        return AlertDialog(
          title: const Text('Novi termin'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Izbor zaposlenog — samo admin. Običnom zaposlenom se
                    // termin automatski veže za njegov nalog, pa ovo ne vidi.
                    if (isAdmin) ...[
                      DropdownButtonFormField<int>(
                        value: employeeId,
                        decoration:
                            const InputDecoration(labelText: 'Zaposleni'),
                        items: [
                          for (final e in employees)
                            DropdownMenuItem(
                              value: e.id,
                              child: Text(e.name ?? 'Zaposleni ${e.id}'),
                            ),
                        ],
                        onChanged: (v) => setState(() => employeeId = v),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: customerName,
                      decoration:
                          const InputDecoration(labelText: 'Ime klijenta'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: phone,
                      decoration:
                          const InputDecoration(labelText: 'Telefon klijenta'),
                    ),
                    const SizedBox(height: 12),
                    // Prikaz izabranog vremena + dugme za izmjenu.
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.schedule),
                      title: const Text('Početak termina'),
                      subtitle: Text(Format.dateTime(startTime)),
                      trailing: TextButton(
                        onPressed: pickDateTime,
                        child: const Text('Izmijeni'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: duration,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Trajanje (min)'),
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        if (n == null || n < 1) return 'Unesite broj minuta';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: price,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration:
                          const InputDecoration(labelText: 'Cijena usluge (€)'),
                      validator: (v) {
                        final n = double.tryParse((v ?? '').replaceAll(',', '.'));
                        if (n == null || n < 0) return 'Unesite ispravnu cijenu';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: note,
                      decoration:
                          const InputDecoration(labelText: 'Napomena (opciono)'),
                    ),
                  ],
                ),
              ),
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
                  AppointmentRequest(
                    employeeId: employeeId,
                    customerName: customerName.text.trim().isEmpty
                        ? null
                        : customerName.text.trim(),
                    customerPhone: phone.text.trim().isEmpty
                        ? null
                        : phone.text.trim(),
                    // .toUtc() => serijalizuje se sa oznakom zone „Z“, što server
                    // zahtijeva (isto kao kod izvještaja). Bez toga vraća grešku 400.
                    startTime: startTime.toUtc(),
                    duration: int.parse(duration.text),
                    servicePrice:
                        double.parse(price.text.replaceAll(',', '.')),
                    note: note.text.trim().isEmpty ? null : note.text.trim(),
                  ),
                );
              },
              child: const Text('Sačuvaj'),
            ),
          ],
        );
      },
    ),
  );
}
