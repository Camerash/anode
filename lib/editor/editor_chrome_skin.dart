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
