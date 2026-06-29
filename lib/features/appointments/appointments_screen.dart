import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'day_schedule_view.dart';

/// Ekran „Termini“ — prikazuje dnevni raspored (Excel tabela sa slotovima).
///
/// Namjerno je jednostavan: bez kartica/TabBar-a, samo raspored. Time
/// izbjegavamo komplikovane `Stack` rasporede koji su na web-u pravili
/// probleme sa veličinom (layout greške). Lista svih termina se može
/// kasnije dodati kao zaseban ekran ako zatreba.
class AppointmentsScreen extends ConsumerWidget {
  const AppointmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // DayScheduleView je već Scaffold (ima svoj FloatingActionButton).
    return const DayScheduleView();
  }
}
