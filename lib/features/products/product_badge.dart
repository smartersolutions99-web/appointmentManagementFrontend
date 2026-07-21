import 'package:flutter/material.dart';

/// Boja zalihe: crveno ≤ 3, žuto ≤ 10, zeleno inače.
Color stockColor(int? quantity) {
  final q = quantity ?? 0;
  if (q <= 3) return Colors.red;
  if (q <= 10) return Colors.orange;
  return Colors.green;
}

/// Mali bedž koji prikazuje trenutnu zalihu, obojen prema količini.
class QuantityBadge extends StatelessWidget {
  final int? quantity;

  const QuantityBadge({super.key, required this.quantity});

  @override
  Widget build(BuildContext context) {
    final color = stockColor(quantity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        '${quantity ?? 0}',
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }
}
