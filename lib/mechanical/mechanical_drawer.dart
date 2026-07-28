import 'package:flutter/widgets.dart';

import '../vfd/vfd_widgets.dart';
import 'mechanical_feedback.dart';

class MechanicalDrawer extends StatefulWidget {
  const MechanicalDrawer({
    super.key,
    required this.open,
    required this.width,
    required this.palette,
    required this.onOpenChanged,
    required this.child,
    this.soundEnabled = true,
    this.hapticsEnabled = true,
  });

  final bool open;
  final double width;
  final VfdPalette palette;
  final ValueChanged<bool> onOpenChanged;
  final Widget child;
  final bool soundEnabled;
  final bool hapticsEnabled;

  @override
  State<MechanicalDrawer> createState() => _MechanicalDrawerState();
}

class _MechanicalDrawerState extends State<MechanicalDrawer>
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
  void didUpdateWidget(covariant MechanicalDrawer oldWidget) {
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
  Widget build(BuildContext context) => SizedBox(
    key: const ValueKey('mechanical-drawer'),
    width: widget.width,
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final x = (1 - _travel.value) * widget.width;
        return Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned.fill(
              child: Transform.translate(
                offset: Offset(x, 0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF050807),
                    border: Border(
                      left: BorderSide(
                        color: widget.palette.unlit.withValues(alpha: 0.45),
                        width: 2,
                      ),
                    ),
                  ),
                  child: widget.child,
                ),
              ),
            ),
            Positioned(
              left: -44,
              top: 22,
              width: 44,
              height: 52,
              child: Transform.translate(
                offset: Offset(x, 0),
                child: Semantics(
                  button: true,
                  toggled: widget.open,
                  label: widget.open
                      ? 'Close service drawer'
                      : 'Open service drawer',
                  child: GestureDetector(
                    key: const ValueKey('mechanical-drawer-latch'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => widget.onOpenChanged(!widget.open),
                    child: CustomPaint(
                      painter: _DrawerLatchPainter(
                        palette: widget.palette,
                        pointsLeft: widget.open,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _DrawerLatchPainter extends CustomPainter {
  const _DrawerLatchPainter({required this.palette, required this.pointsLeft});

  final VfdPalette palette;
  final bool pointsLeft;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (pointsLeft) {
      path
        ..moveTo(5, size.height / 2)
        ..lineTo(size.width - 4, 4)
        ..lineTo(size.width - 4, size.height - 4);
    } else {
      path
        ..moveTo(size.width - 5, size.height / 2)
        ..lineTo(4, 4)
        ..lineTo(4, size.height - 4);
    }
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
  bool shouldRepaint(covariant _DrawerLatchPainter oldDelegate) =>
      oldDelegate.palette != palette || oldDelegate.pointsLeft != pointsLeft;
}
