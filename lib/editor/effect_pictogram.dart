import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../model/optical_profile.dart';
import '../vfd/vfd_widgets.dart';

class EffectPictogram extends StatelessWidget {
  const EffectPictogram({
    super.key,
    required this.id,
    required this.palette,
    required this.lit,
    this.enabled = true,
  });

  final String id;
  final VfdPalette palette;
  final bool lit;
  final bool enabled;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _EffectPictogramPainter(
      id: id,
      color: palette.state(lit).withValues(alpha: enabled ? 0.96 : 0.28),
      glow: lit && enabled,
    ),
  );
}

class _EffectPictogramPainter extends CustomPainter {
  const _EffectPictogramPainter({
    required this.id,
    required this.color,
    required this.glow,
  });

  final String id;
  final Color color;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width, size.height) / 32;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter;
    if (glow) paint.maskFilter = const MaskFilter.blur(BlurStyle.solid, 1.6);
    switch (id) {
      case EffectIds.emission:
        _ray(canvas, paint);
      case EffectIds.bloom:
        _rings(canvas, paint);
      case EffectIds.phosphorTexture:
        _texture(canvas, paint);
      case EffectIds.gridMesh:
        _grid(canvas, paint);
      case EffectIds.unlitPhosphor:
        _segment(canvas, paint);
      case EffectIds.phosphorDecay:
        _decay(canvas, paint);
      case EffectIds.glassGrain:
        _grain(canvas, paint);
      case EffectIds.filamentWires:
        _filaments(canvas, paint);
      case EffectIds.tiltParallax:
        _parallax(canvas, paint);
      case '__phosphor__':
        _phosphor(canvas, paint);
      default:
        _unknown(canvas, paint);
    }
    canvas.restore();
  }

  void _ray(Canvas canvas, Paint paint) {
    final path = Path()
      ..moveTo(-8, -12)
      ..lineTo(1, -3)
      ..lineTo(-3, -3)
      ..lineTo(8, 12)
      ..lineTo(-1, 3)
      ..lineTo(3, 3)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _rings(Canvas canvas, Paint paint) {
    canvas.drawCircle(Offset.zero, 3, paint);
    canvas.drawCircle(Offset.zero, 8, paint);
    canvas.drawCircle(Offset.zero, 13, paint);
  }

  void _texture(Canvas canvas, Paint paint) {
    for (var y = -10.0; y <= 10; y += 5) {
      for (var x = -10.0; x <= 10; x += 5) {
        final stagger = (y ~/ 5).isEven ? 1.0 : -1.0;
        canvas.drawCircle(Offset(x + stagger, y), 1, paint);
      }
    }
  }

  void _grid(Canvas canvas, Paint paint) {
    for (var p = -9.0; p <= 9; p += 6) {
      canvas.drawLine(Offset(p, -12), Offset(p, 12), paint);
      canvas.drawLine(Offset(-12, p), Offset(12, p), paint);
    }
  }

  void _segment(Canvas canvas, Paint paint) {
    final path = Path()
      ..moveTo(-9, -11)
      ..lineTo(9, -11)
      ..lineTo(12, -8)
      ..lineTo(9, -5)
      ..lineTo(-9, -5)
      ..lineTo(-12, -8)
      ..close();
    canvas.drawPath(path, paint);
    canvas.drawPath(path.shift(const Offset(0, 16)), paint);
  }

  void _decay(Canvas canvas, Paint paint) {
    for (var i = 0; i < 4; i++) {
      final alpha = 1 - i * 0.22;
      canvas.drawLine(
        Offset(-12 + i * 5, -9 + i * 3),
        Offset(-2 + i * 5, 9 - i * 3),
        paint..color = color.withValues(alpha: color.a * alpha),
      );
    }
  }

  void _grain(Canvas canvas, Paint paint) {
    const points = <Offset>[
      Offset(-10, -8),
      Offset(-3, -11),
      Offset(7, -7),
      Offset(11, 1),
      Offset(4, 8),
      Offset(-6, 10),
      Offset(-11, 2),
      Offset(1, 0),
    ];
    for (final point in points) {
      canvas.drawCircle(point, 1.4, paint);
    }
  }

  void _filaments(Canvas canvas, Paint paint) {
    for (final y in <double>[-7, 0, 7]) {
      canvas.drawLine(Offset(-13, y), Offset(13, y), paint);
    }
    canvas.drawLine(const Offset(-9, -11), const Offset(-9, 11), paint);
    canvas.drawLine(const Offset(9, -11), const Offset(9, 11), paint);
  }

  void _parallax(Canvas canvas, Paint paint) {
    canvas.drawRect(const Rect.fromLTWH(-11, -9, 17, 17), paint);
    canvas.drawRect(const Rect.fromLTWH(-5, -5, 17, 17), paint);
    canvas.drawLine(const Offset(-13, 11), const Offset(-7, 11), paint);
    canvas.drawLine(const Offset(-10, 8), const Offset(-7, 11), paint);
    canvas.drawLine(const Offset(-10, 14), const Offset(-7, 11), paint);
  }

  void _phosphor(Canvas canvas, Paint paint) {
    canvas.drawCircle(Offset.zero, 4, paint);
    canvas.drawOval(const Rect.fromLTWH(-13, -6, 26, 12), paint);
    canvas.save();
    canvas.rotate(math.pi / 3);
    canvas.drawOval(const Rect.fromLTWH(-13, -6, 26, 12), paint);
    canvas.rotate(math.pi / 3);
    canvas.drawOval(const Rect.fromLTWH(-13, -6, 26, 12), paint);
    canvas.restore();
  }

  void _unknown(Canvas canvas, Paint paint) {
    final text = TextPainter(
      text: TextSpan(
        text: '?',
        style: TextStyle(
          color: paint.color,
          fontFamily: 'Barlow Condensed',
          fontSize: 26,
          fontStyle: FontStyle.italic,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, -text.size.center(Offset.zero));
  }

  @override
  bool shouldRepaint(covariant _EffectPictogramPainter oldDelegate) =>
      oldDelegate.id != id ||
      oldDelegate.color != color ||
      oldDelegate.glow != glow;
}
