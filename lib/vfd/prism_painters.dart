part of 'prism_widgets.dart';

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
    _drawOuterFrame(canvas, outer);

    final pocket = RRect.fromRectAndRadius(
      Rect.fromLTRB(4.5, 4.5, size.width - 4.5, size.height - 4.5),
      const Radius.circular(0.8),
    );
    _drawPocket(canvas, size, pocket);
    if (hovered && enabled) _drawHover(canvas, pocket);
    if (selected || focused) _drawLocators(canvas, size);
  }

  void _drawOuterFrame(Canvas canvas, RRect outer) {
    canvas.drawRRect(
      outer,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0xFF070908),
            Color(0xFF171B19),
            Color(0xFF050606),
          ],
          stops: <double>[0, 0.36, 1],
        ).createShader(outer.outerRect),
    );
  }

  void _drawPocket(Canvas canvas, Size size, RRect pocket) {
    canvas.drawRRect(
      pocket,
      Paint()
        ..color = const Color(0xFF010202)
        ..maskFilter = const MaskFilter.blur(BlurStyle.inner, 1.8),
    );
    canvas.drawLine(
      Offset(4.5, size.height - 4),
      Offset(size.width - 4.5, size.height - 4),
      Paint()
        ..strokeWidth = 0.7
        ..color = const Color(0xFF66706B).withValues(alpha: 0.18),
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
    required this.pressed,
  });

  final VfdPalette palette;
  final PrismStyle style;
  final bool lit;
  final bool enabled;
  final bool pressed;

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = _PrismCapGeometry.from(size, style, enabled: enabled);
    _drawBody(canvas, size, geometry);
    _drawFace(canvas, geometry);
    if (lit) _drawBacklight(canvas, geometry);
    _drawEdges(canvas, size, geometry);
  }

  void _drawBody(Canvas canvas, Size size, _PrismCapGeometry geometry) {
    canvas.drawPath(
      geometry.body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            const Color(0xFF69736E).withValues(alpha: 0.62 * geometry.opacity),
            const Color(0xFF171C1A).withValues(alpha: 0.98 * geometry.opacity),
            const Color(0xFF070908).withValues(alpha: geometry.opacity),
            const Color(0xFF4A524E).withValues(alpha: 0.42 * geometry.opacity),
          ],
          stops: const <double>[0, 0.24, 0.72, 1],
        ).createShader(Offset.zero & size),
    );
  }

  void _drawFace(Canvas canvas, _PrismCapGeometry geometry) {
    final smoke = style.faceOpacity.clamp(0.60, 0.95);
    canvas.drawRRect(
      geometry.face,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color.lerp(
              const Color(0xFF252B28),
              const Color(0xFF080A09),
              smoke,
            )!.withValues(alpha: geometry.opacity),
            const Color(0xFF050706).withValues(alpha: geometry.opacity),
            const Color(0xFF101512).withValues(alpha: geometry.opacity),
          ],
          stops: const <double>[0, 0.44, 1],
        ).createShader(geometry.face.outerRect),
    );
  }

  void _drawBacklight(Canvas canvas, _PrismCapGeometry geometry) {
    canvas.drawRRect(
      geometry.face,
      Paint()
        ..shader = RadialGradient(
          radius: 0.78,
          colors: <Color>[
            palette.lit.withValues(
              alpha: 0.13 * style.activeLuminosity * geometry.opacity,
            ),
            palette.lit.withValues(
              alpha: 0.035 * style.activeLuminosity * geometry.opacity,
            ),
            Colors.transparent,
          ],
          stops: const <double>[0, 0.58, 1],
        ).createShader(geometry.face.outerRect),
    );
  }

  void _drawEdges(Canvas canvas, Size size, _PrismCapGeometry geometry) {
    final face = geometry.face;
    final opacity = geometry.opacity;
    canvas.drawRRect(
      face,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.65
        ..color = const Color(0xFF9EA7A2).withValues(alpha: 0.42 * opacity),
    );
    canvas.drawLine(
      Offset(face.left + 1, face.top),
      Offset(face.right - 1, face.top),
      _edgePaint(
        pressed ? 0.7 : 1.15,
        0.48,
        opacity,
        color: const Color(0xFFE0E4E1),
      ),
    );
    canvas.drawLine(
      Offset(face.left, face.top + 1),
      Offset(face.left, face.bottom - 1),
      _edgePaint(0.65, 0.24, opacity, color: const Color(0xFFBFC6C2)),
    );
    canvas.drawLine(
      Offset(face.left + size.width * 0.09, face.top + 1.4),
      Offset(face.right - size.width * 0.24, face.top + 1.4),
      _edgePaint(0.55, 0.20, opacity),
    );
  }

  Paint _edgePaint(
    double width,
    double alpha,
    double opacity, {
    Color color = const Color(0xFFFFFFFF),
  }) => Paint()
    ..strokeWidth = width
    ..color = color.withValues(alpha: alpha * opacity);

  @override
  bool shouldRepaint(covariant _PrismCapPainter oldDelegate) =>
      oldDelegate.palette != palette ||
      oldDelegate.style != style ||
      oldDelegate.lit != lit ||
      oldDelegate.enabled != enabled ||
      oldDelegate.pressed != pressed;
}

class _PrismCapGeometry {
  const _PrismCapGeometry({
    required this.body,
    required this.face,
    required this.opacity,
  });

  factory _PrismCapGeometry.from(
    Size size,
    PrismStyle style, {
    required bool enabled,
  }) {
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
        left + side * 0.50,
        top + side * 0.55,
        right - side * 0.50,
        bottom - side * 0.72,
      ),
      Radius.circular(size.height * 0.018),
    );
    return _PrismCapGeometry(
      body: body,
      face: face,
      opacity: enabled ? 1 : 0.52,
    );
  }

  final Path body;
  final RRect face;
  final double opacity;

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
