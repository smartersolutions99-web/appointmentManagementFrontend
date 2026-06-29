import 'package:flutter/material.dart';

/// Paleta boja za barbere. Boju dodjeljujemo stabilno na osnovu ID-a zaposlenog
/// (isti barber uvijek dobije istu boju), pa je koristimo i u agendi i u legendi.
const List<Color> kBarberPalette = <Color>[
  Color(0xFF1E88E5), // plava
  Color(0xFF43A047), // zelena
  Color(0xFFF4511E), // narandžasta
  Color(0xFF8E24AA), // ljubičasta
  Color(0xFF00897B), // tirkizna
  Color(0xFFD81B60), // roze
  Color(0xFF6D4C41), // smeđa
  Color(0xFF3949AB), // indigo
];

/// Vraća boju za datog barbera. Ako ID nije poznat, vraća sivu.
Color barberColor(int? employeeId) {
  if (employeeId == null) return Colors.grey;
  // Modulo po dužini palete — uvijek dobijemo postojeću boju.
  return kBarberPalette[employeeId.abs() % kBarberPalette.length];
}
