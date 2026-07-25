import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Slatka animacija učitavanja: makaze koje škljocaju i pramenovi kose koji
/// padaju (brend salona). Koristi se umjesto običnog spinnera.
class ScissorsLoader extends StatefulWidget {
  final double size;
  final Color? color;

  const ScissorsLoader({super.key, this.size = 48, this.color});

  @override
  State<ScissorsLoader> createState() => _ScissorsLoaderState();
}

class _ScissorsLoaderState extends State<ScissorsLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) =>
            CustomPaint(painter: _ScissorsPainter(_c.value, color)),
      ),
    );
  }
}

class _ScissorsPainter extends CustomPainter {
  final double t; // 0..1 (napredak animacije)
  final Color color;

  _ScissorsPainter(this.t, this.color);

  double _deg(double d) => d * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final pivot = Offset(w * 0.5, h * 0.56); // šraf makaza

    // Otvorenost (0=zatvoreno, 1=otvoreno) — glatko škljoca (sinus).
    final open = math.sin(t * 2 * math.pi) * 0.5 + 0.5;
    final theta = _deg(7 + open * 18); // ugao kraka od vertikale (7°..25°)

    final bladeLen = h * 0.40;
    final handleLen = h * 0.20;
    final ringR = w * 0.085;

    final metal = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.06
      ..strokeCap = StrokeCap.round;
    final ringPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.05;

    // Dva ukrštena kraka (svaki: prsten dole → šraf → sječivo gore).
    for (final s in [1.0, -1.0]) {
      // Smjer sječiva: naviše, nagnuto za s*theta.
      final bladeDir = Offset(math.sin(s * theta), -math.cos(s * theta));
      final ringDir = -bladeDir; // prsten je na suprotnoj strani (ukrštanje)

      final tip = pivot + bladeDir * bladeLen;
      final ringBase = pivot + ringDir * handleLen;
      final ringCenter = ringBase + ringDir * ringR;

      canvas.drawLine(pivot, tip, metal); // sječivo
      canvas.drawLine(pivot, ringBase, metal); // krak do prstena
      canvas.drawCircle(ringCenter, ringR, ringPaint); // prsten za prste
    }

    // Šraf u sredini.
    canvas.drawCircle(pivot, w * 0.05, Paint()..color = color);

    // Pramenovi kose koji padaju (iznad makaza, blijede dok padaju).
    final hair = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.035
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final phase = (t + i / 3) % 1.0; // svaki pramen u svojoj fazi
      final x = w * (0.30 + i * 0.20);
      final y = h * 0.06 + phase * h * 0.42; // pada nadolje
      final len = h * 0.12 * (1 - phase); // kraći pri kraju pada
      final op = (1 - phase) * 0.5;
      hair.color = color.withValues(alpha: op.clamp(0.0, 1.0));
      // Malo talasast pramen.
      final path = Path()
        ..moveTo(x, y)
        ..relativeQuadraticBezierTo(w * 0.05, len * 0.5, 0, len);
      canvas.drawPath(path, hair);
    }
  }

  @override
  bool shouldRepaint(covariant _ScissorsPainter old) =>
      old.t != t || old.color != color;
}
