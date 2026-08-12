import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../shared/format.dart';
import 'customer_autocomplete.dart';

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
  required ApiService api, // rezerva za našaptavanje (ako adresar nije učitan)
  required List<CustomerResponse> customers, // adresar za našaptavanje klijenata
}) {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final phone = TextEditingController();
  final price = TextEditingController();
  int? serviceId;
  // Popunjava se kad se klijent izabere iz liste našaptavanja (pretraga po
  // telefonu vraća i id). Server tada veže termin za postojećeg klijenta.
  int? customerId;

  final endTime = startTime.add(Duration(minutes: durationMinutes));

  return showDialog<AppointmentRequest>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        // Kad se izabere postojeći klijent, predloži uslugu i cijenu sa njegovog
        // poslednjeg ZAVRŠENOG termina. Na 204/grešku — bez prefila.
        Future<void> prefillLastService(int? id) async {
          if (id == null) return;
          try {
            final last = await api.getLastService(id);
            if (last == null || !context.mounted) return;
            setState(() {
              if (last.serviceId != null &&
                  services.any((s) => s.id == last.serviceId)) {
                serviceId = last.serviceId;
              }
              if (last.servicePrice != null) {
                price.text = last.servicePrice!.toString();
              }
            });
          } catch (_) {
            // nema prefila
          }
        }

        return AlertDialog(
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
                  CustomerAutocompleteField(
                    api: api,
                    directory: customers,
                    controller: name,
                    otherController: phone,
                    label: 'Ime i prezime',
                    byPhone: false,
                    onCustomerSelected: (id) {
                      customerId = id;
                      prefillLastService(id);
                    },
                  ),
                  const SizedBox(height: 12),
                  CustomerAutocompleteField(
                    api: api,
                    directory: customers,
                    controller: phone,
                    otherController: name,
                    label: 'Telefon',
                    byPhone: true,
                    onCustomerSelected: (id) {
                      customerId = id;
                      prefillLastService(id);
                    },
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
                  customerId: customerId,
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
        );
      },
    ),
  );
}
