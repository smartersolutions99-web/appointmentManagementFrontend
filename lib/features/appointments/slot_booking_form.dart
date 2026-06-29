import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../shared/format.dart';

/// Forma koja se otvara nakon što se u rasporedu izaberu slobodna polja.
///
/// Vrijeme početka i trajanje su već određeni izborom polja, pa se ovdje unose
/// samo: ime i prezime klijenta, telefon, usluga (popuni cijenu) i cijena.
Future<AppointmentRequest?> showSlotBookingForm(
  BuildContext context, {
  required DateTime startTime, // lokalno vrijeme početka
  required int durationMinutes,
  required int? employeeId,
  required List<ServiceEntityResponse> services,
}) {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final phone = TextEditingController();
  final price = TextEditingController();
  int? serviceId;

  final endTime = startTime.add(Duration(minutes: durationMinutes));

  return showDialog<AppointmentRequest>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Zakaži termin'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Prikaz izabranog termina (samo informativno).
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${Format.dateTime(startTime)} – ${Format.time(endTime)}'
                      '  ($durationMinutes min)',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  TextFormField(
                    controller: name,
                    decoration:
                        const InputDecoration(labelText: 'Ime i prezime'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Telefon'),
                  ),
                  const SizedBox(height: 12),
                  // Izbor usluge — kad se izabere, automatski popuni cijenu.
                  DropdownButtonFormField<int>(
                    value: serviceId,
                    decoration: const InputDecoration(labelText: 'Usluga'),
                    items: [
                      for (final s in services)
                        DropdownMenuItem(
                          value: s.id,
                          child: Text(s.name ?? 'Usluga ${s.id}'),
                        ),
                    ],
                    onChanged: (v) {
                      setState(() {
                        serviceId = v;
                        // Predloži cijenu iz izabrane usluge.
                        ServiceEntityResponse? selected;
                        for (final s in services) {
                          if (s.id == v) {
                            selected = s;
                            break;
                          }
                        }
                        if (selected?.basicPrice != null) {
                          price.text = selected!.basicPrice!.toString();
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: price,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(labelText: 'Cijena (€)'),
                    validator: (v) {
                      final n =
                          double.tryParse((v ?? '').replaceAll(',', '.'));
                      if (n == null || n < 0) return 'Unesite ispravnu cijenu';
                      return null;
                    },
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
                  serviceId: serviceId,
                  customerName:
                      name.text.trim().isEmpty ? null : name.text.trim(),
                  customerPhone:
                      phone.text.trim().isEmpty ? null : phone.text.trim(),
                  // .toUtc() => šaljemo sa zonom „Z“ kako server zahtijeva.
                  startTime: startTime.toUtc(),
                  duration: durationMinutes,
                  servicePrice:
                      double.parse(price.text.replaceAll(',', '.')),
                ),
              );
            },
            child: const Text('Zakaži'),
          ),
        ],
      ),
    ),
  );
}
