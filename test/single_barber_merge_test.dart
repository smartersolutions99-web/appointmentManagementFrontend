import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Replika strukture iz `_buildTable` (pojedinačni prikaz barbera):
/// vertikalni skrol → Row[ satnica (Column min), Expanded(blokovi, Column min) ].
/// Cilj: potvrditi da spojeni blok termina od više slotova NE baca layout grešku
/// i da se tekst prikaže JEDNOM (a ne u svakom slotu).
void main() {
  testWidgets('Spojeni blok termina — bez layout greške, tekst jednom',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const cellH = 52.0;
    const n = 12;

    Widget timeStrip() => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < n; i++)
              SizedBox(height: cellH, child: Center(child: Text('t$i'))),
          ],
        );

    // Klijent kolona: blok termina od 2 slota (tekst jednom) + slobodne ćelije.
    Widget clientCol() => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: cellH * 2,
              child: Container(
                color: Colors.blue,
                alignment: Alignment.centerLeft,
                child: const Text('Termin X'),
              ),
            ),
            for (var i = 0; i < n - 2; i++)
              SizedBox(
                  height: cellH,
                  child: Container(alignment: Alignment.centerLeft)),
          ],
        );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            const SizedBox(height: 30), // zaglavlje
            Expanded(
              child: SingleChildScrollView(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 64, child: timeStrip()),
                    Expanded(child: clientCol()),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 40), // footer
          ],
        ),
      ),
    ));

    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Termin X'), findsOneWidget); // termin jednom, ne ponovljen
  });
}
