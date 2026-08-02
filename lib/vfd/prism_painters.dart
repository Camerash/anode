part of 'prism_widgets.dart';

class _PrismSymbolPainter extends CustomPainter {
  const _PrismSymbolPainter({
    required this.symbol,
    required this.color,
    required this.glowColor,
    required this.glow,
  });

  final PrismSymbol symbol;
  final Color color;
  final Color glowColor;
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final path = PrismSymbolGeometry.path(symbol, size);
    if (glow > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..color = glowColor.withValues(alpha: 0.44 * glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _PrismSymbolPainter oldDelegate) =>
      oldDelegate.symbol != symbol ||
      oldDelegate.color != color ||
      oldDelegate.glowColor != glowColor ||
      oldDelegate.glow != glow;
}

class _PrismHousingPainter extends CustomPainter {
  const _PrismHousingPainter({
    required this.palette,
    required this.selected,
    required this.focused,
    required this.hovered,
    required this.enabled,
  });

  final VfdPalette palette;
  final bool selected;
  final bool focused;
  final bool hovered;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = RRect.fromRectAndRadius(
      Rect.fromLTRB(2, 2, size.width - 2, size.height - 2),
      const Radius.circular(1.4),
    );
    final pocket = RRect.fromRectAndRadius(
      Rect.fromLTRB(4.5, 4.5, size.width - 4.5, size.height - 4.5),
      const Radius.circular(0.8),
    );
    _drawOuterFrame(canvas, size, outer, pocket);
    _drawPocket(canvas, pocket);
    if (hovered && enabled) _drawHover(canvas, pocket);
    if (selected || focused) _drawLocators(canvas, size);
  }

  void _drawOuterFrame(Canvas canvas, Size size, RRect outer, RRect pocket) {
    canvas.drawDRRect(
      outer,
      pocket,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0x7A89938E),
            Color(0x52313A36),
            Color(0x8A101412),
          ],
          stops: <double>[0, 0.36, 1],
        ).createShader(outer.outerRect),
    );
    final highlight = Paint()
      ..strokeWidth = 0.65
      ..color = const Color(0x78DDE4E0);
    canvas.drawLine(
      Offset(outer.left + 2, outer.top),
      Offset(outer.right - 2, outer.top),
      highlight,
    );
    canvas.drawLine(
      Offset(outer.left, outer.top + 2),
      Offset(outer.left, size.height * 0.58),
      highlight..color = const Color(0x42DDE4E0),
    );
  }

  void _drawPocket(Canvas canvas, RRect pocket) {
    final gasketOpening = RRect.fromRectAndRadius(
      pocket.outerRect.deflate(1.6),
      const Radius.circular(0.5),
    );
    canvas.drawDRRect(
      pocket,
      gasketOpening,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xA8090B0A), Color(0xD4010202)],
        ).createShader(pocket.outerRect),
    );
    canvas.drawLine(
      Offset(pocket.left + 1, pocket.bottom),
      Offset(pocket.right - 1, pocket.bottom),
      Paint()
        ..strokeWidth = 0.8
        ..color = const Color(0x9C000000),
    );
  }

  void _drawHover(Canvas canvas, RRect pocket) {
    canvas.drawRRect(
      pocket,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7
        ..color = const Color(0xFFCED5D1).withValues(alpha: 0.16),
    );
  }

  void _drawLocators(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = focused ? 1.5 : 1
      ..color = (focused ? palette.lit : palette.unlit).withValues(
        alpha: focused ? 0.92 : 0.58,
      );
    const length = 4.5;
    const inset = 0.5;
    _drawLocatorCorner(
      canvas,
      paint,
      const Offset(inset, inset),
      const Offset(1, 1),
      length,
      verticalFirst: true,
    );
    _drawLocatorCorner(
      canvas,
      paint,
      Offset(size.width - inset, inset),
      const Offset(-1, 1),
      length,
      verticalFirst: false,
    );
    _drawLocatorCorner(
      canvas,
      paint,
      Offset(inset, size.height - inset),
      const Offset(1, -1),
      length,
      verticalFirst: true,
    );
    _drawLocatorCorner(
      canvas,
      paint,
      Offset(size.width - inset, size.height - inset),
      const Offset(-1, -1),
      length,
      verticalFirst: false,
    );
  }

  void _drawLocatorCorner(
    Canvas canvas,
    Paint paint,
    Offset corner,
    Offset direction,
    double length, {
    required bool verticalFirst,
  }) {
    final horizontalEnd = corner + Offset(direction.dx * length, 0);
    final verticalEnd = corner + Offset(0, direction.dy * length);
    if (verticalFirst) {
      canvas.drawLine(corner, verticalEnd, paint);
      canvas.drawLine(corner, horizontalEnd, paint);
      return;
    }
    canvas.drawLine(corner, horizontalEnd, paint);
    canvas.drawLine(corner, verticalEnd, paint);
  }

  @override
  bool shouldRepaint(covariant _PrismHousingPainter oldDelegate) =>
      oldDelegate.palette != palette ||
      oldDelegate.selected != selected ||
      oldDelegate.focused != focused ||
      oldDelegate.hovered != hovered ||
      oldDelegate.enabled != enabled;
}

class _PrismCapPainter extends CustomPainter {
  const _PrismCapPainter({
    required this.palette,
    required this.style,
    required this.lit,
    required this.enabled,
    required this.pressProgress,
  });

  final VfdPalette palette;
  final PrismStyle style;
  final bool lit;
  final bool enabled;
  final double pressProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = _PrismCapGeometry.from(
      size,
      style,
      pressProgress: pressProgress,
    );
    _drawBody(canvas, size, geometry);
    _drawFace(canvas, geometry);
    if (lit) _drawBacklight(canvas, geometry);
    _drawEdges(canvas, size, geometry);
  }

  void _drawBody(Canvas canvas, Size size, _PrismCapGeometry geometry) {
    final opticalDensity = style.faceOpacity.clamp(0.60, 0.95);
    final bevelDensity = (opticalDensity + 0.10).clamp(0.0, 1.0);
    canvas.drawPath(
      geometry.body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            const Color(0xFF69736E).withValues(alpha: bevelDensity * 0.78),
            const Color(0xFF171C1A).withValues(alpha: bevelDensity * 0.92),
            const Color(0xFF070908).withValues(alpha: bevelDensity),
            const Color(0xFF4A524E).withValues(alpha: bevelDensity * 0.66),
          ],
          stops: const <double>[0, 0.24, 0.72, 1],
        ).createShader(Offset.zero & size),
    );
  }

  void _drawFace(Canvas canvas, _PrismCapGeometry geometry) {
    final faceCoverage =
        (_prismFaceCoverage(style.faceOpacity) + pressProgress * 0.02).clamp(
          0.0,
          1.0,
        );
    canvas.drawRRect(
      geometry.face,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            const Color(0xFF252B28).withValues(alpha: faceCoverage * 0.78),
            const Color(0xFF050706).withValues(alpha: faceCoverage),
            const Color(0xFF101512).withValues(alpha: faceCoverage * 0.90),
          ],
          stops: const <double>[0, 0.44, 1],
        ).createShader(geometry.face.outerRect),
    );
  }

  void _drawBacklight(Canvas canvas, _PrismCapGeometry geometry) {
    final electricalLuminosity = enabled ? 1.0 : 0.48;
    canvas.drawRRect(
      geometry.face,
      Paint()
        ..shader = RadialGradient(
          radius: 0.78,
          colors: <Color>[
            palette.lit.withValues(
              alpha: 0.13 * style.activeLuminosity * electricalLuminosity,
            ),
            palette.lit.withValues(
              alpha: 0.035 * style.activeLuminosity * electricalLuminosity,
            ),
            const Color(0x00000000),
          ],
          stops: const <double>[0, 0.58, 1],
        ).createShader(geometry.face.outerRect),
    );
  }

  void _drawEdges(Canvas canvas, Size size, _PrismCapGeometry geometry) {
    final face = geometry.face;
    final progress = pressProgress.clamp(0.0, 1.0);
    canvas.drawRRect(
      face,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.65
        ..color = const Color(
          0xFF9EA7A2,
        ).withValues(alpha: 0.42 - progress * 0.24),
    );
    canvas.drawRRect(
      face,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.45 + progress * 0.40
        ..color = const Color(
          0xFF000000,
        ).withValues(alpha: 0.10 + progress * 0.34),
    );
    canvas.drawLine(
      Offset(face.left + 1, face.top),
      Offset(face.right - 1, face.top),
      _edgePaint(
        1.15 - progress * 0.45,
        0.48 - progress * 0.28,
        color: const Color(0xFFE0E4E1),
      ),
    );
    canvas.drawLine(
      Offset(face.left, face.top + 1),
      Offset(face.left, face.bottom - 1),
      _edgePaint(0.65, 0.24 - progress * 0.12, color: const Color(0xFFBFC6C2)),
    );
    canvas.drawLine(
      Offset(face.left + size.width * 0.09, face.top + 1.4),
      Offset(face.right - size.width * 0.24, face.top + 1.4),
      _edgePaint(0.55, 0.20 - progress * 0.10),
    );
    final directionalContactAlpha = 0.30 - progress * 0.12;
    canvas.drawLine(
      Offset(face.left + 1, face.bottom),
      Offset(face.right - 1, face.bottom),
      _edgePaint(0.8, directionalContactAlpha, color: const Color(0xFF000000)),
    );
    canvas.drawLine(
      Offset(face.right, face.top + 1),
      Offset(face.right, face.bottom - 1),
      _edgePaint(
        0.7,
        directionalContactAlpha * 0.72,
        color: const Color(0xFF000000),
      ),
    );
  }

  Paint _edgePaint(
    double width,
    double alpha, {
    Color color = const Color(0xFFFFFFFF),
  }) => Paint()
    ..strokeWidth = width
    ..color = color.withValues(alpha: alpha);

  @override
  bool shouldRepaint(covariant _PrismCapPainter oldDelegate) =>
      oldDelegate.palette != palette ||
      oldDelegate.style != style ||
      oldDelegate.lit != lit ||
      oldDelegate.enabled != enabled ||
      oldDelegate.pressProgress != pressProgress;
}

double _prismFaceCoverage(double opticalDensity) {
  // Smoke density describes absorption, not raw layer alpha. Keeping even the
  // lightest cap above 0.8 preserves its physical shell over busy substrates.
  final normalized = (opticalDensity.clamp(0.60, 0.95) - 0.60) / (0.95 - 0.60);
  return 0.82 + normalized * (0.97 - 0.82);
}

class _PrismCapGeometry {
  const _PrismCapGeometry({required this.body, required this.face});

  factory _PrismCapGeometry.from(
    Size size,
    PrismStyle style, {
    required double pressProgress,
  }) {
    final progress = pressProgress.clamp(0.0, 1.0);
    final depthScale = (style.bevelDepth / 0.12).clamp(0.55, 1.45);
    final side = (size.height * 0.115 * depthScale).clamp(3.2, 8.0);
    final left = size.height * 0.105;
    final right = size.width - left;
    final top = size.height * 0.105;
    final bottom = size.height - size.height * 0.105;
    final corner = size.height * 0.055;
    final body = _bodyPath(
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      side: side,
      corner: corner,
    );
    final face = RRect.fromRectAndRadius(
      Rect.fromLTRB(
        left + side * (0.50 - progress * 0.15),
        top + side * (0.55 - progress * 0.17),
        right - side * (0.50 - progress * 0.15),
        bottom - side * (0.72 - progress * 0.22),
      ),
      Radius.circular(size.height * 0.018),
    );
    return _PrismCapGeometry(body: body, face: face);
  }

  final Path body;
  final RRect face;

  static Path _bodyPath({
    required double left,
    required double right,
    required double top,
    required double bottom,
    required double side,
    required double corner,
  }) => Path()
    ..moveTo(left + corner, top)
    ..lineTo(right - corner, top)
    ..lineTo(right, top + side * 0.72)
    ..lineTo(right + side * 0.34, bottom - side * 0.42)
    ..lineTo(right - corner * 0.20, bottom)
    ..lineTo(left + corner * 0.20, bottom)
    ..lineTo(left - side * 0.34, bottom - side * 0.42)
    ..lineTo(left, top + side * 0.72)
    ..close();
}
