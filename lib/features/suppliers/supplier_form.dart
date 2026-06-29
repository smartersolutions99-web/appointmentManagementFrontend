import 'package:flutter/material.dart';

import '../../models/models.dart';

/// Forma za unos/izmjenu dobavljača (iskačući prozor). Vraća [SupplierRequest]
/// ili `null` ako je otkazano. Samo ADMIN je otvara (gating je na ekranu).
class SupplierForm extends StatefulWidget {
  final SupplierResponse? existing;

  const SupplierForm({super.key, this.existing});

  @override
  State<SupplierForm> createState() => _SupplierFormState();
}

class _SupplierFormState extends State<SupplierForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _contact;
  String _contactType = 'phoneNumber';

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _contact = TextEditingController(text: widget.existing?.contactValue ?? '');
    _contactType = widget.existing?.contactType ?? 'phoneNumber';
  }

  @override
  void dispose() {
    _name.dispose();
    _contact.dispose();
    super.dispose();
  }

  /// Stavke padajuće liste za tip kontakta (uz zaštitu od nepoznate vrijednosti).
  List<DropdownMenuItem<String>> _contactTypeItems() {
    final options = <String, String>{
      'phoneNumber': 'Telefon',
      'email': 'Email',
    };
    if (!options.containsKey(_contactType)) {
      options[_contactType] = _contactType;
    }
    return [
      for (final e in options.entries)
        DropdownMenuItem(value: e.key, child: Text(e.value)),
    ];
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final request = SupplierRequest(
      name: _name.text.trim(),
      contactType: _contactType,
      contactValue:
          _contact.text.trim().isEmpty ? null : _contact.text.trim(),
    );
    Navigator.of(context).pop(request);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? 'Izmijeni dobavljača' : 'Novi dobavljač'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Naziv'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Obavezno polje' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _contactType,
              decoration: const InputDecoration(labelText: 'Tip kontakta'),
              items: _contactTypeItems(),
              onChanged: (v) =>
                  setState(() => _contactType = v ?? 'phoneNumber'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _contact,
              decoration:
                  const InputDecoration(labelText: 'Kontakt (broj/email)'),
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

/// Otvara formu i vraća [SupplierRequest] ili `null` ako je otkazano.
Future<SupplierRequest?> showSupplierForm(
  BuildContext context, {
  SupplierResponse? existing,
}) {
  return showDialog<SupplierRequest>(
    context: context,
    builder: (_) => SupplierForm(existing: existing),
  );
}
