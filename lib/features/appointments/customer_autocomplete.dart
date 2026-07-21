import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/api_service.dart';

/// Jedan rezultat pretrage klijenta koji prikazujemo u padajućem meniju.
///
/// Ujedinjuje dva različita odgovora sa servera:
/// - pretraga po imenu (`/api/customers/search`) vraća samo ime i telefon;
/// - pretraga po telefonu (`/api/customers/by-phone`) vraća i `id` klijenta.
class CustomerHit {
  final String? name;
  final String? phone;
  final int? id; // poznat samo kod pretrage po telefonu

  const CustomerHit({this.name, this.phone, this.id});
}

/// Polje za unos imena ili telefona klijenta sa „našaptavanjem“ (autocomplete).
///
/// Dok korisnik kuca, ispod polja se otvara lista postojećih klijenata koji se
/// poklapaju sa unosom. Kad se jedan izabere, popune se OBA polja (ime i
/// telefon), a ako znamo `id` klijenta prosljeđujemo ga formi preko
/// [onCustomerSelected] (da server veže termin za postojećeg klijenta).
///
/// Isti widget se koristi za oba polja — razlika je samo [byPhone]:
/// - `byPhone: false` → pretraga po imenu, u polju se prikazuje ime;
/// - `byPhone: true`  → pretraga po telefonu, u polju se prikazuje telefon.
class CustomerAutocompleteField extends StatefulWidget {
  /// API preko kojeg tražimo klijente (rezerva, ako adresar nije učitan).
  final ApiService api;

  /// Unaprijed učitan adresar klijenata. Ako nije prazan, filtriramo LOKALNO
  /// (trenutno, bez poziva servera). Ako je prazan (npr. učitavanje zakazalo),
  /// padamo nazad na žive endpointe preko [api].
  final List<CustomerResponse> directory;

  /// Kontroler OVOG polja (ime ili telefon) — iz njega forma čita uneseni tekst.
  final TextEditingController controller;

  /// Kontroler DRUGOG polja, koji automatski popunimo kad se klijent izabere
  /// (ako je ovo polje za ime, ovdje ide telefon i obrnuto).
  final TextEditingController otherController;

  /// Natpis iznad polja (npr. „Ime klijenta“).
  final String label;

  /// `true` → tražimo po broju telefona; `false` → po imenu.
  final bool byPhone;

  /// Poziva se kad se klijent izabere iz liste (ili kad korisnik nastavi da
  /// kuca, sa `null` — jer tada više ne znamo o kom klijentu je riječ).
  final ValueChanged<int?> onCustomerSelected;

  const CustomerAutocompleteField({
    super.key,
    required this.api,
    required this.directory,
    required this.controller,
    required this.otherController,
    required this.label,
    required this.byPhone,
    required this.onCustomerSelected,
  });

  @override
  State<CustomerAutocompleteField> createState() =>
      _CustomerAutocompleteFieldState();
}

class _CustomerAutocompleteFieldState extends State<CustomerAutocompleteField> {
  // RawAutocomplete zahtijeva svoj FocusNode; pravimo ga ovdje i brišemo u dispose.
  final FocusNode _focusNode = FocusNode();

  // „Debounce“ tajmer — ne šaljemo zahtjev na svaki pritisak tastera, nego tek
  // kad korisnik na kratko zastane, da ne zatrpamo server.
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  /// Traži klijente za uneseni tekst.
  ///
  /// Ako imamo učitan adresar → filtriramo LOKALNO i vraćamo odmah (trenutna
  /// reakcija, bez servera). Inače (rezerva) zovemo server uz debounce od 300 ms,
  /// da ne šaljemo zahtjev na svaki pritisak tastera.
  FutureOr<Iterable<CustomerHit>> _search(String query) {
    final text = query.trim();
    // Prekratak unos → ne otvaramo listu (da izbjegnemo ogromne rezultate).
    if (text.length < 2) return const <CustomerHit>[];

    // Glavni put: lokalno filtriranje učitanog adresara.
    if (widget.directory.isNotEmpty) return _filterLocal(text);

    // Rezervni put: živi endpoint uz debounce. Ako korisnik nastavi da kuca,
    // prethodni tajmer se otkaže i taj (zastarjeli) `Future` se nikad ne ispuni
    // — RawAutocomplete ionako koristi samo posljednji poziv.
    _debounce?.cancel();
    final completer = Completer<Iterable<CustomerHit>>();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final results = await _fetch(text);
      if (!completer.isCompleted) completer.complete(results);
    });
    return completer.future;
  }

  /// Filtrira učitan adresar lokalno. Za ime: „sadrži" (mala/velika slova nisu
  /// bitna). Za telefon: poredimo SAMO cifre, pa poklapanje radi bez obzira na
  /// razmake/crtice u zapisu broja (npr. „067 555" ⟶ „067555").
  Iterable<CustomerHit> _filterLocal(String text) {
    final q = text.toLowerCase();
    final digitsQ = text.replaceAll(RegExp(r'\D'), '');
    final matches = <CustomerHit>[];
    for (final c in widget.directory) {
      bool hit;
      if (widget.byPhone) {
        final digitsField = (c.contactValue ?? '').replaceAll(RegExp(r'\D'), '');
        hit = digitsQ.isNotEmpty && digitsField.contains(digitsQ);
      } else {
        hit = (c.name ?? '').toLowerCase().contains(q);
      }
      if (hit) {
        matches.add(
          CustomerHit(name: c.name, phone: c.contactValue, id: c.id),
        );
        if (matches.length >= 30) break; // ne prikazuj ogromne liste
      }
    }
    return matches;
  }

  /// Stvarni poziv servera. Sve je u try/catch — ako endpoint zakaže, samo
  /// vratimo praznu listu (polje nastavlja da radi kao običan unos).
  Future<List<CustomerHit>> _fetch(String text) async {
    try {
      if (widget.byPhone) {
        final hits = await widget.api.findCustomersByPhone(text);
        return [
          for (final c in hits)
            CustomerHit(name: c.name, phone: c.contactValue, id: c.id),
        ];
      } else {
        final hits = await widget.api.searchCustomers(text);
        return [
          for (final c in hits) CustomerHit(name: c.name, phone: c.phone),
        ];
      }
    } catch (_) {
      return const <CustomerHit>[];
    }
  }

  /// Tekst koji upišemo u OVO polje kad se klijent izabere.
  String _displayFor(CustomerHit hit) =>
      (widget.byPhone ? hit.phone : hit.name) ?? '';

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<CustomerHit>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      displayStringForOption: _displayFor,
      optionsBuilder: (value) => _search(value.text),
      onSelected: (hit) {
        // Popuni DRUGO polje (ime ↔ telefon) podacima izabranog klijenta.
        final other = widget.byPhone ? hit.name : hit.phone;
        if (other != null && other.isNotEmpty) {
          widget.otherController.text = other;
        }
        // Ako znamo id klijenta (pretraga po telefonu), javi ga formi.
        widget.onCustomerSelected(hit.id);
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: widget.byPhone ? TextInputType.phone : null,
          decoration: InputDecoration(labelText: widget.label),
          // Kad korisnik SAM mijenja tekst, više ne znamo o kom je klijentu
          // riječ, pa poništavamo prethodno zapamćeni id.
          onChanged: (_) => widget.onCustomerSelected(null),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              // Ograniči veličinu padajuće liste da ne prekrije cijeli dijalog.
              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 400),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final hit = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    title: Text(hit.name ?? '(bez imena)'),
                    subtitle: hit.phone == null ? null : Text(hit.phone!),
                    onTap: () => onSelected(hit),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
