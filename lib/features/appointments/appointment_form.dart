import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../shared/format.dart';
import 'customer_autocomplete.dart';

/// Forma za kreiranje novog termina.
///
/// Vraća [AppointmentRequest] ili `null` ako je otkazano. Zbog biranja datuma
/// i vremena koristimo `StatefulBuilder` da dijalog može osvježavati prikaz.
Future<AppointmentRequest?> showAppointmentForm(
  BuildContext context, {
  required bool isAdmin,
  int? currentEmployeeId,
  required List<EmployeeResponse> employees,
  DateTime? initialStart,
  required ApiService api, // rezerva za našaptavanje (ako adresar nije učitan)
  required List<CustomerResponse> customers, // adresar za našaptavanje klijenata
  AppointmentResponse? existing, // ako je zadat → IZMJENA postojećeg termina
  List<ServiceEntityResponse> services = const [], // padajući izbor usluge
}) {
  final isEdit = existing != null;
  final formKey = GlobalKey<FormState>();
  final customerName =
      TextEditingController(text: existing?.customerName ?? '');
  final phone = TextEditingController(text: existing?.customerPhone ?? '');
  final duration =
      TextEditingController(text: (existing?.duration ?? 30).toString());
  final price = TextEditingController(
      text: existing?.servicePrice != null
          ? existing!.servicePrice!.toString()
          : '');
  final note = TextEditingController(text: existing?.note ?? '');
  // Popunjava se kad se klijent izabere iz liste našaptavanja (pretraga po
  // telefonu vraća i id). Server tada veže termin za postojećeg klijenta.
  int? customerId = existing?.customerId;
  int? serviceId = existing?.serviceId;

  // Barber: pri izmjeni zadržavamo postojećeg; inače admin bira, običnom zakucan.
  int? employeeId =
      existing?.employeeId ?? (isAdmin ? null : currentEmployeeId);
  // Početno vrijeme: postojeći termin → njegov početak; inače zadato ili sljedeći sat.
  DateTime startTime;
  if (existing?.startTime != null) {
    startTime = existing!.startTime!.toLocal();
  } else if (initialStart != null) {
    startTime = initialStart;
  } else {
    final t = DateTime.now().add(const Duration(hours: 1));
    startTime = DateTime(t.year, t.month, t.day, t.hour);
  }

  return showDialog<AppointmentRequest>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        // Otvara biranje datuma pa vremena i ažurira `startTime`.
        Future<void> pickDateTime() async {
          final date = await showDatePicker(
            context: context,
            initialDate: startTime,
            // Kod izmjene dozvoljavamo i prošle datume (termin može biti raniji);
            // kod novog termina ne dozvoljavamo prošlost.
            firstDate: isEdit
                ? DateTime(2020)
                : DateTime.now().subtract(const Duration(days: 1)),
            lastDate: DateTime.now().add(const Duration(days: 365)),
          );
          if (date == null || !context.mounted) return;

          final time = await showTimePicker(
            context: context,
            initialTime: TimeOfDay.fromDateTime(startTime),
            initialEntryMode: TimePickerEntryMode.input, // po difoltu unos brojki
            // 24-časovni prikaz (bez AM/PM).
            builder: (ctx, child) => MediaQuery(
              data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
              child: child!,
            ),
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
          title: Text(isEdit ? 'Izmjena termina' : 'Novi termin'),
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
                    CustomerAutocompleteField(
                      api: api,
                      directory: customers,
                      controller: customerName,
                      otherController: phone,
                      label: 'Ime klijenta',
                      byPhone: false,
                      onCustomerSelected: (id) => customerId = id,
                    ),
                    const SizedBox(height: 12),
                    CustomerAutocompleteField(
                      api: api,
                      directory: customers,
                      controller: phone,
                      otherController: customerName,
                      label: 'Telefon klijenta',
                      byPhone: true,
                      onCustomerSelected: (id) => customerId = id,
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
                    // Izbor usluge (opciono) — kad se izabere, popuni cijenu.
                    if (services.isNotEmpty) ...[
                      DropdownButtonFormField<int>(
                        value: serviceId,
                        decoration: const InputDecoration(
                            labelText: 'Usluga (opciono)'),
                        items: [
                          const DropdownMenuItem<int>(
                              value: null, child: Text('— bez usluge —')),
                          for (final s in services)
                            DropdownMenuItem(
                              value: s.id,
                              child: Text(s.name ?? 'Usluga ${s.id}'),
                            ),
                        ],
                        onChanged: (v) {
                          setState(() {
                            serviceId = v;
                            ServiceEntityResponse? sel;
                            for (final s in services) {
                              if (s.id == v) {
                                sel = s;
                                break;
                              }
                            }
                            if (sel?.basicPrice != null) {
                              price.text = sel!.basicPrice!.toString();
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
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
                    serviceId: serviceId,
                    customerId: customerId,
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
