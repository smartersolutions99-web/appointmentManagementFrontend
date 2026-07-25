import 'package:flutter/material.dart';

/// Zajednički mjesečni birač i nazivi mjeseci (koristi se na više kalendara).

const List<String> _months = [
  'Januar', 'Februar', 'Mart', 'April', 'Maj', 'Jun',
  'Jul', 'Avgust', 'Septembar', 'Oktobar', 'Novembar', 'Decembar',
];

/// Naziv mjeseca (1..12), npr. "Avgust".
String monthName(int month) => _months[month - 1];

/// Naziv mjeseca + godina, npr. "Avgust 2026".
String monthLabel(DateTime m) => '${_months[m.month - 1]} ${m.year}';

/// Otvara mali dijalog za izbor SAMO mjeseca (Flutter nema ugrađen mjesečni
/// birač). Vraća prvi dan izabranog mjeseca ili `null` (otkazano).
Future<DateTime?> showMonthPicker(BuildContext context, DateTime initial) {
  return showDialog<DateTime>(
    context: context,
    builder: (_) => _MonthPickerDialog(initial: initial),
  );
}

class _MonthPickerDialog extends StatefulWidget {
  final DateTime initial;
  const _MonthPickerDialog({required this.initial});

  @override
  State<_MonthPickerDialog> createState() => _MonthPickerDialogState();
}

class _MonthPickerDialogState extends State<_MonthPickerDialog> {
  late int _year = widget.initial.year;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // Zaglavlje: izbor godine (‹ 2026 ›).
      title: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Prethodna godina',
            onPressed: () => setState(() => _year--),
          ),
          Expanded(
            child: Center(
              child: Text('$_year',
                  style: Theme.of(context).textTheme.titleLarge),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Sljedeća godina',
            onPressed: () => setState(() => _year++),
          ),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: GridView.count(
          shrinkWrap: true,
          crossAxisCount: 3,
          childAspectRatio: 2.1,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [for (var m = 1; m <= 12; m++) _monthTile(m)],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Otkaži'),
        ),
      ],
    );
  }

  Widget _monthTile(int m) {
    final selected = m == widget.initial.month && _year == widget.initial.year;
    final label = Text(
      _months[m - 1],
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 13),
    );
    void pick() => Navigator.pop(context, DateTime(_year, m, 1));
    return selected
        ? FilledButton(onPressed: pick, child: label)
        : OutlinedButton(onPressed: pick, child: label);
  }
}
