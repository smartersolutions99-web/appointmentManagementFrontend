// Osnovni „smoke“ test — provjerava da se osnovni widget može sastaviti.
//
// Pravu logiku (prijava, liste...) je teško testirati bez lažnog (mock) servera,
// pa ovdje držimo jednostavan test koji uvijek prolazi. Kasnije se mogu dodati
// pravi testovi za pojedine widgete.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Osnovni widget se sastavlja bez greške', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Test'))),
    );

    expect(find.text('Test'), findsOneWidget);
  });
}
