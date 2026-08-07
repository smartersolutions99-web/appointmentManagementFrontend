import 'package:flutter/material.dart';

import '../../models/models.dart';

/// Forma za unos/izmjenu zaposlenog (dialog).
class EmployeeForm extends StatefulWidget {
  final EmployeeResponse? existing;
  final List<RoleResponse> roles;
  final List<SellingPlaceResponse> sellingPlaces;

  const EmployeeForm({
    super.key,
    this.existing,
    required this.roles,
    required this.sellingPlaces,
  });

  @override
  State<EmployeeForm> createState() => _EmployeeFormState();
}

class _EmployeeFormState extends State<EmployeeForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _duration;
  late final TextEditingController _commission;

  int? _roleId;
  int? _sellingPlaceId;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _username = TextEditingController(text: e?.username ?? '');
    _password = TextEditingController();
    _phone = TextEditingController(text: e?.phoneNumber ?? '');
    _email = TextEditingController(text: e?.email ?? '');
    _duration = TextEditingController(
        text: e?.defaultAppointmentDuration?.toString() ?? '');
    _commission = TextEditingController(text: _fmtCommission(e?.commission));
    _roleId = e?.roleId;
    _sellingPlaceId = e?.sellingPlaceId;
  }

  /// Procenat za prikaz u polju: cijeli broj bez ".0" (npr. 50), inače decimalno.
  static String _fmtCommission(double? v) {
    if (v == null) return '';
    return v % 1 == 0 ? v.toInt().toString() : v.toString();
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _password.dispose();
    _phone.dispose();
    _email.dispose();
    _duration.dispose();
    _commission.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final request = EmployeeRequest(
      name: _name.text.trim(),
      username: _username.text.trim(),
      // Pri izmjeni, prazno polje lozinke znači „ne mijenjaj lozinku“.
      password: _password.text.isEmpty ? null : _password.text,
      roleId: _roleId,
      sellingPlaceId: _sellingPlaceId,
      phoneNumber: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      email: _email.text.trim().isEmpty ? null : _email.text.trim(),
      // Prazno → null (server zadržava/postavlja svoju podrazumijevanu vrijednost).
      defaultAppointmentDuration: _duration.text.trim().isEmpty
          ? null
          : int.tryParse(_duration.text.trim()),
      // Procenat (provizija) zaposlenog. Prazno → null (ne mijenja se).
      commission: _commission.text.trim().isEmpty
          ? null
          : double.tryParse(_commission.text.trim().replaceAll(',', '.')),
    );
    Navigator.pop(context, request);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    return AlertDialog(
      title: Text(isEdit ? 'Izmijeni zaposlenog' : 'Novi zaposleni'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Form(
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
                TextFormField(
                  controller: _username,
                  decoration: const InputDecoration(labelText: 'Korisničko ime'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Obavezno polje' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: isEdit
                        ? 'Nova lozinka (opciono)'
                        : 'Lozinka',
                  ),
                  validator: (v) {
                    // Lozinka je obavezna samo pri kreiranju.
                    if (!isEdit && (v == null || v.isEmpty)) {
                      return 'Obavezno polje';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                // Padajuća lista uloga.
                DropdownButtonFormField<int>(
                  value: _roleId,
                  decoration: const InputDecoration(labelText: 'Uloga'),
                  items: [
                    for (final role in widget.roles)
                      DropdownMenuItem(
                        value: role.id,
                        child: Text(role.naziv ?? 'Uloga ${role.id}'),
                      ),
                  ],
                  onChanged: (v) => setState(() => _roleId = v),
                ),
                const SizedBox(height: 12),
                // Padajuća lista prodajnih mjesta.
                DropdownButtonFormField<int>(
                  value: _sellingPlaceId,
                  decoration: const InputDecoration(labelText: 'Prodajno mjesto'),
                  items: [
                    for (final place in widget.sellingPlaces)
                      DropdownMenuItem(
                        value: place.id,
                        child: Text(place.name ?? 'Mjesto ${place.id}'),
                      ),
                  ],
                  onChanged: (v) => setState(() => _sellingPlaceId = v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  decoration: const InputDecoration(labelText: 'Telefon'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _duration,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Trajanje termina (min)',
                    helperText:
                        'Na koliko minuta se dijeli raspored pri zakazivanju (npr. 30).',
                  ),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return null; // opciono
                    final n = int.tryParse(t);
                    if (n == null || n < 1) return 'Unesite broj minuta (≥ 1)';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _commission,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Procenat (%)',
                    suffixText: '%',
                    helperText:
                        'Provizija zaposlenog. Koristi se u izvještaju po zaposlenom.',
                  ),
                  validator: (v) {
                    final t = (v ?? '').trim().replaceAll(',', '.');
                    if (t.isEmpty) return null; // opciono
                    final n = double.tryParse(t);
                    if (n == null || n < 0 || n > 100) {
                      return 'Unesite procenat 0–100';
                    }
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
        FilledButton(onPressed: _save, child: const Text('Sačuvaj')),
      ],
    );
  }
}
