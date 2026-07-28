import 'package:flutter/widgets.dart';

import '../vfd/vfd_widgets.dart';
import 'mechanical_feedback.dart';

enum MechanicalDrawerEdge { right, bottom }

/// Service bay that physically consumes workspace while opening.
///
/// The child canvas receives the remaining constraints. Drawer contents retain
/// their full layout extent behind a clipping aperture during travel.
class MechanicalPushDrawer extends StatefulWidget {
  const MechanicalPushDrawer({
    super.key,
    required this.open,
    required this.edge,
    required this.extent,
    required this.palette,
    required this.onOpenChanged,
    required this.content,
    required this.drawer,
    this.soundEnabled = true,
    this.hapticsEnabled = true,
  });

  final bool open;
  final MechanicalDrawerEdge edge;
  final double extent;
  final VfdPalette palette;
  final ValueChanged<bool> onOpenChanged;
  final Widget content;
  final Widget drawer;
  final bool soundEnabled;
  final bool hapticsEnabled;

  @override
  State<MechanicalPushDrawer> createState() => _MechanicalPushDrawerState();
}

class _MechanicalPushDrawerState extends State<MechanicalPushDrawer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    value: widget.open ? 1 : 0,
  );
  late final Animation<double> _travel =
      TweenSequence<double>(<TweenSequenceItem<double>>[
        TweenSequenceItem<double>(tween: ConstantTween<double>(0), weight: 20),
        TweenSequenceItem<double>(
          tween: Tween<double>(begin: 0, end: 1),
          weight: 130,
        ),
        TweenSequenceItem<double>(
          tween: Tween<double>(begin: 1.018, end: 1),
          weight: 30,
        ),
      ]).animate(_controller);

  @override
  void didUpdateWidget(covariant MechanicalPushDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.open == widget.open) return;
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduced) {
      _controller.value = widget.open ? 1 : 0;
    } else if (widget.open) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
    actuateMechanicalFeedback(
      soundEnabled: widget.soundEnabled,
      hapticsEnabled: widget.hapticsEnabled,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final reserved = widget.extent * _travel.value.clamp(0.0, 1.0);
      return Stack(
        key: const ValueKey('mechanical-push-drawer'),
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: <Widget>[
          if (widget.edge == MechanicalDrawerEdge.right)
            Row(
              children: <Widget>[
                Expanded(child: widget.content),
                _horizontalDrawer(reserved),
              ],
            )
          else
            Column(
              children: <Widget>[
                Expanded(child: widget.content),
                _verticalDrawer(reserved),
              ],
            ),
          _latch(reserved),
        ],
      );
    },
  );

  Widget _horizontalDrawer(double reserved) => SizedBox(
    width: reserved,
    child: ClipRect(
      child: OverflowBox(
        alignment: Alignment.centerLeft,
        minWidth: widget.extent,
        maxWidth: widget.extent,
        child: _drawerBody(
          border: Border(
            left: BorderSide(
              color: widget.palette.unlit.withValues(alpha: 0.45),
              width: 2,
            ),
          ),
        ),
      ),
    ),
  );

  Widget _verticalDrawer(double reserved) => SizedBox(
    height: reserved,
    child: ClipRect(
      child: OverflowBox(
        alignment: Alignment.topCenter,
        minHeight: widget.extent,
        maxHeight: widget.extent,
        child: _drawerBody(
          border: Border(
            top: BorderSide(
              color: widget.palette.unlit.withValues(alpha: 0.45),
              width: 2,
            ),
          ),
        ),
      ),
    ),
  );

  Widget _drawerBody({required Border border}) => DecoratedBox(
    decoration: BoxDecoration(color: const Color(0xFF050807), border: border),
    child: widget.drawer,
  );

  Widget _latch(double reserved) {
    final right = widget.edge == MechanicalDrawerEdge.right;
    return Positioned(
      right: right ? reserved : null,
      bottom: right ? null : reserved,
      top: right ? 22 : null,
      left: right ? null : 0,
      width: right ? 44 : null,
      height: right ? 52 : 44,
      child: right
          ? _latchControl(
              label: widget.open
                  ? 'Close service drawer'
                  : 'Open service drawer',
              painter: _PushDrawerLatchPainter(
                palette: widget.palette,
                direction: widget.open
                    ? _LatchDirection.right
                    : _LatchDirection.left,
              ),
            )
          : Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 52,
                height: 44,
                child: _latchControl(
                  label: widget.open
                      ? 'Close service drawer'
                      : 'Open service drawer',
                  painter: _PushDrawerLatchPainter(
                    palette: widget.palette,
                    direction: widget.open
                        ? _LatchDirection.down
                        : _LatchDirection.up,
                  ),
                ),
              ),
            ),
    );
  }

  Widget _latchControl({
    required String label,
    required CustomPainter painter,
  }) => Semantics(
    button: true,
    toggled: widget.open,
    label: label,
    child: GestureDetector(
      key: const ValueKey('mechanical-drawer-latch'),
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onOpenChanged(!widget.open),
      child: CustomPaint(painter: painter),
    ),
  );
}

enum _LatchDirection { left, right, up, down }

class _PushDrawerLatchPainter extends CustomPainter {
  const _PushDrawerLatchPainter({
    required this.palette,
    required this.direction,
  });

  final VfdPalette palette;
  final _LatchDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    final path = switch (direction) {
      _LatchDirection.left =>
        Path()
          ..moveTo(5, size.height / 2)
          ..lineTo(size.width - 4, 4)
          ..lineTo(size.width - 4, size.height - 4),
      _LatchDirection.right =>
        Path()
          ..moveTo(size.width - 5, size.height / 2)
          ..lineTo(4, 4)
          ..lineTo(4, size.height - 4),
      _LatchDirection.up =>
        Path()
          ..moveTo(size.width / 2, 5)
          ..lineTo(4, size.height - 4)
          ..lineTo(size.width - 4, size.height - 4),
      _LatchDirection.down =>
        Path()
          ..moveTo(size.width / 2, size.height - 5)
          ..lineTo(4, 4)
          ..lineTo(size.width - 4, 4),
    };
    path.close();
    canvas.drawPath(path, Paint()..color = const Color(0xFF15201C));
    canvas.drawPath(
      path,
      Paint()
        ..color = palette.unlit.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _PushDrawerLatchPainter oldDelegate) =>
      oldDelegate.palette != palette || oldDelegate.direction != direction;
}
