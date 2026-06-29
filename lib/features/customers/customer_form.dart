import 'package:flutter/material.dart';

import '../../models/models.dart';

/// Forma za unos/izmjenu klijenta, prikazana kao iskačući prozor (dialog).
///
/// Otvara se funkcijom [showCustomerForm]. Ako proslijedimo postojećeg klijenta,
/// forma je u režimu izmjene; u suprotnom je u režimu kreiranja.
class CustomerForm extends StatefulWidget {
  final CustomerResponse? existing;

  const CustomerForm({super.key, this.existing});

  @override
  State<CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends State<CustomerForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _contact;

  // Tip kontakta biramo iz padajuće liste.
  String _contactType = 'PHONE';

  @override
  void initState() {
    super.initState();
    // Ako uređujemo postojećeg klijenta, popuni polja njegovim podacima.
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _contact = TextEditingController(text: widget.existing?.contactValue ?? '');
    _contactType = widget.existing?.contactType ?? 'phoneNumber';
  }

  /// Gradi stavke padajuće liste za tip kontakta.
  ///
  /// Server koristi vrijednosti poput „phoneNumber“ i „email“. Ako postojeći
  /// klijent ima neku drugu/nepoznatu vrijednost, dodajemo je u listu da
  /// `DropdownButton` ne bi pukao (mora postojati tačno jedna stavka sa tom
  /// vrijednošću).
  List<DropdownMenuItem<String>> _buildContactTypeItems() {
    final options = <String, String>{
      'phoneNumber': 'Telefon',
      'email': 'Email',
    };
    if (!options.containsKey(_contactType)) {
      options[_contactType] = _contactType;
    }
    return [
      for (final entry in options.entries)
        DropdownMenuItem(value: entry.key, child: Text(entry.value)),
    ];
  }

  @override
  void dispose() {
    _name.dispose();
    _contact.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    // Sastavi zahtjev i vrati ga onome ko je otvorio formu.
    final request = CustomerRequest(
      name: _name.text.trim(),
      contactValue: _contact.text.trim(),
      contactType: _contactType,
      sellingPlaceId: widget.existing?.sellingPlaceId,
    );
    Navigator.of(context).pop(request);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    return AlertDialog(
      title: Text(isEdit ? 'Izmijeni klijenta' : 'Novi klijent'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Ime i prezime'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Obavezno polje' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _contactType,
              decoration: const InputDecoration(labelText: 'Tip kontakta'),
              items: _buildContactTypeItems(),
              onChanged: (v) =>
                  setState(() => _contactType = v ?? 'phoneNumber'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _contact,
              decoration: const InputDecoration(labelText: 'Kontakt (broj/email)'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Obavezno polje' : null,
            ),
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
}

/// Otvara formu i vraća uneseni [CustomerRequest] ili `null` ako je otkazano.
Future<CustomerRequest?> showCustomerForm(
  BuildContext context, {
  CustomerResponse? existing,
}) {
  return showDialog<CustomerRequest>(
    context: context,
    builder: (_) => CustomerForm(existing: existing),
  );
}
