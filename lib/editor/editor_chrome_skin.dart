import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../mechanical/mechanical_push_drawer.dart';
import '../model/optical_profile.dart';
import '../vfd/prism_widgets.dart';
import '../vfd/vfd_widgets.dart';

enum EditorChromeSurfaceRole { header, dock }

enum EditorChromeSymbol { undo, redo }

/// Visual vocabulary for editor chrome. Layout and interaction stay outside
/// the skin so later dashboard families can replace materials without changing
/// editor behavior.
abstract interface class EditorChromeSkin {
  Widget surface({
    Key? key,
    required EditorChromeSurfaceRole role,
    required EdgeInsets padding,
    required Widget child,
  });

  Widget button({
    Key? key,
    required String label,
    required VoidCallback? onPressed,
    EditorChromeSymbol? symbol,
    bool lit,
    bool selected,
    bool enabled,
    bool compact,
    bool dense,
  });

  Widget title(String text, {Key? key});

  Widget divider({required Axis axis, bool dense});

  Widget dragHandle({required Axis axis, required bool active, bool dense});

  Widget dockTargetIndicator({required Axis axis});

  Widget layoutSpecimen({
    Key? diagramKey,
    required double aspect,
    required String ratio,
    required bool selected,
    required bool focused,
    required bool hovered,
    required bool enabled,
  });

  Widget consoleSurface({
    required MechanicalDrawerEdge edge,
    required EdgeInsets safeInsets,
    required Widget child,
  });
}

class VfdEditorChromeSkin implements EditorChromeSkin {
  const VfdEditorChromeSkin({required this.palette, required this.prismStyle});

  final VfdPalette palette;
  final PrismStyle prismStyle;

  @override
  Widget surface({
    Key? key,
    required EditorChromeSurfaceRole role,
    required EdgeInsets padding,
    required Widget child,
  }) => PrismPanel(
    key: key,
    palette: palette,
    surfaceOpacity: switch (role) {
      EditorChromeSurfaceRole.header => 0.94,
      EditorChromeSurfaceRole.dock => 0.90,
    },
    padding: padding,
    child: child,
  );

  @override
  Widget button({
    Key? key,
    required String label,
    required VoidCallback? onPressed,
    EditorChromeSymbol? symbol,
    bool lit = false,
    bool selected = false,
    bool enabled = true,
    bool compact = false,
    bool dense = false,
  }) => PrismButton(
    key: key,
    label: label,
    symbol: switch (symbol) {
      EditorChromeSymbol.undo => PrismSymbol.undo,
      EditorChromeSymbol.redo => PrismSymbol.redo,
      null => null,
    },
    palette: palette,
    role: dense
        ? PrismRole.micro
        : compact
        ? PrismRole.compact
        : PrismRole.standard,
    style: prismStyle,
    lit: lit,
    selected: selected,
    enabled: enabled,
    onPressed: onPressed,
  );

  @override
  Widget title(String text, {Key? key}) => KeyedSubtree(
    key: key,
    child: VfdLegend(
      text,
      palette: palette,
      lit: true,
      size: 12,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  );

  @override
  Widget divider({required Axis axis, bool dense = false}) => ColoredBox(
    color: palette.unlit.withValues(alpha: 0.34),
    child: SizedBox(
      width: axis == Axis.horizontal ? 1 : 30,
      height: axis == Axis.horizontal ? (dense ? 24 : 30) : 1,
    ),
  );

  @override
  Widget dragHandle({
    required Axis axis,
    required bool active,
    bool dense = false,
  }) => CustomPaint(
    key: const ValueKey('editor-dock-handle-dots'),
    painter: _VfdDockHandlePainter(
      color: (active ? palette.lit : palette.unlit).withValues(
        alpha: active ? 0.92 : 0.62,
      ),
      dense: dense,
    ),
  );

  @override
  Widget dockTargetIndicator({required Axis axis}) => ColoredBox(
    color: palette.lit.withValues(alpha: 0.18),
    child: SizedBox(
      width: axis == Axis.horizontal ? double.infinity : 2,
      height: axis == Axis.horizontal ? 2 : double.infinity,
    ),
  );

  @override
  Widget layoutSpecimen({
    Key? diagramKey,
    required double aspect,
    required String ratio,
    required bool selected,
    required bool focused,
    required bool hovered,
    required bool enabled,
  }) => Builder(
    builder: (context) => TweenAnimationBuilder<double>(
      tween: Tween<double>(end: selected ? 1 : 0),
      duration: (MediaQuery.maybeDisableAnimationsOf(context) ?? false)
          ? Duration.zero
          : const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      builder: (context, selection, child) => CustomPaint(
        painter: _VfdLayoutSpecimenPainter(
          palette: palette,
          selection: selection,
          focused: focused,
          hovered: hovered,
          enabled: enabled,
        ),
        child: child,
      ),
      child: Opacity(
        opacity: enabled || selected ? 1 : 0.34,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            children: <Widget>[
              Expanded(
                child: SizedBox(
                  width: double.infinity,
                  child: CustomPaint(
                    key: diagramKey,
                    painter: _VfdLayoutDiagramPainter(
                      aspect: aspect,
                      color: enabled || selected ? palette.lit : palette.unlit,
                      selected: selected,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 7),
              VfdLegend(
                ratio,
                palette: palette,
                lit: selected,
                size: 10,
                maxLines: 1,
                overflow: TextOverflow.clip,
              ),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  Widget consoleSurface({
    required MechanicalDrawerEdge edge,
    required EdgeInsets safeInsets,
    required Widget child,
  }) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFF050807),
      border: switch (edge) {
        MechanicalDrawerEdge.right => Border(
          left: BorderSide(
            color: palette.unlit.withValues(alpha: 0.45),
            width: 2,
          ),
        ),
        MechanicalDrawerEdge.bottom => Border(
          top: BorderSide(
            color: palette.unlit.withValues(alpha: 0.45),
            width: 2,
          ),
        ),
      },
    ),
    child: Padding(
      padding: switch (edge) {
        MechanicalDrawerEdge.right => EdgeInsets.only(
          top: safeInsets.top,
          right: safeInsets.right,
        ),
        MechanicalDrawerEdge.bottom => EdgeInsets.only(
          left: safeInsets.left,
          right: safeInsets.right,
        ),
      },
      child: child,
    ),
  );
}

class _VfdLayoutSpecimenPainter extends CustomPainter {
  const _VfdLayoutSpecimenPainter({
    required this.palette,
    required this.selection,
    required this.focused,
    required this.hovered,
    required this.enabled,
  });

  final VfdPalette palette;
  final double selection;
  final bool focused;
  final bool hovered;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final stateAlpha = enabled ? 1.0 : 0.34;
    canvas.drawRect(
      bounds,
      Paint()
        ..color = Color.lerp(
          const Color(0xFF070B09),
          const Color(0xFF0A1310),
          selection,
        )!.withValues(alpha: stateAlpha),
    );
    canvas.drawRect(
      bounds.deflate(0.75),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 + selection
        ..color = Color.lerp(
          palette.unlit.withValues(alpha: 0.34 * stateAlpha),
          palette.lit.withValues(alpha: 0.92 * stateAlpha),
          selection,
        )!,
    );
    canvas.drawRect(
      bounds.deflate(5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = palette.unlit.withValues(
          alpha: (hovered ? 0.34 : 0.18) * stateAlpha,
        ),
    );
    if (selection > 0) {
      _drawLocators(
        canvas,
        bounds.deflate(4),
        palette.lit.withValues(alpha: 0.82 * selection * stateAlpha),
      );
    }
    if (focused) {
      canvas.drawRect(
        bounds.deflate(8),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = palette.lit.withValues(alpha: 0.72 * stateAlpha),
      );
    }
  }

  void _drawLocators(Canvas canvas, Rect rect, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    const length = 9.0;
    for (final corner in <(Offset, Offset)>[
      (rect.topLeft, const Offset(1, 1)),
      (rect.topRight, const Offset(-1, 1)),
      (rect.bottomLeft, const Offset(1, -1)),
      (rect.bottomRight, const Offset(-1, -1)),
    ]) {
      final point = corner.$1;
      final direction = corner.$2;
      canvas.drawLine(point, point + Offset(direction.dx * length, 0), paint);
      canvas.drawLine(point, point + Offset(0, direction.dy * length), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _VfdLayoutSpecimenPainter oldDelegate) =>
      oldDelegate.palette != palette ||
      oldDelegate.selection != selection ||
      oldDelegate.focused != focused ||
      oldDelegate.hovered != hovered ||
      oldDelegate.enabled != enabled;
}

class _VfdLayoutDiagramPainter extends CustomPainter {
  const _VfdLayoutDiagramPainter({
    required this.aspect,
    required this.color,
    required this.selected,
  });

  final double aspect;
  final Color color;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final available = Size(
      math.max(0, size.width - 6),
      math.max(0, size.height - 6),
    );
    final fitted = applyBoxFit(BoxFit.contain, Size(aspect, 1), available);
    final rect = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 2 : 1.25
        ..color = color.withValues(alpha: selected ? 0.94 : 0.58),
    );
    canvas.drawCircle(
      rect.center,
      selected ? 2 : 1.25,
      Paint()..color = color.withValues(alpha: selected ? 0.9 : 0.46),
    );
  }

  @override
  bool shouldRepaint(covariant _VfdLayoutDiagramPainter oldDelegate) =>
      oldDelegate.aspect != aspect ||
      oldDelegate.color != color ||
      oldDelegate.selected != selected;
}

class _VfdDockHandlePainter extends CustomPainter {
  const _VfdDockHandlePainter({required this.color, required this.dense});

  final Color color;
  final bool dense;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const columns = 3;
    const rows = 2;
    final spacing = dense ? 5.5 : 7.0;
    final origin = Offset(
      (size.width - (columns - 1) * spacing) / 2,
      (size.height - (rows - 1) * spacing) / 2,
    );
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        canvas.drawCircle(
          origin + Offset(column * spacing, row * spacing),
          dense ? 1.35 : 1.7,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _VfdDockHandlePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.dense != dense;
}
