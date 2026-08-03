import 'package:flutter/widgets.dart';

enum MechanicalDrawerEdge { right, bottom }

typedef MechanicalDrawerContentBuilder =
    Widget Function(BuildContext context, double progress);

/// Service bay that physically consumes workspace while opening.
///
/// The child canvas receives the remaining constraints. Drawer contents retain
/// their full layout extent behind a clipping aperture during travel. Surface,
/// safe padding, controls, and feedback belong to the caller.
class MechanicalPushDrawer extends StatefulWidget {
  const MechanicalPushDrawer({
    super.key,
    required this.open,
    required this.edge,
    required this.extent,
    required this.contentBuilder,
    required this.drawer,
  });

  final bool open;
  final MechanicalDrawerEdge edge;
  final double extent;
  final MechanicalDrawerContentBuilder contentBuilder;
  final Widget drawer;

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
      final progress = _travel.value.clamp(0.0, 1.0);
      final reserved = widget.extent * progress;
      return Stack(
        key: const ValueKey('mechanical-push-drawer'),
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: <Widget>[
          if (widget.edge == MechanicalDrawerEdge.right)
            Row(
              children: <Widget>[
                Expanded(
                  child: KeyedSubtree(
                    key: const ValueKey('mechanical-drawer-content'),
                    child: widget.contentBuilder(context, progress),
                  ),
                ),
                _horizontalDrawer(reserved),
              ],
            )
          else
            Column(
              children: <Widget>[
                Expanded(
                  child: KeyedSubtree(
                    key: const ValueKey('mechanical-drawer-content'),
                    child: widget.contentBuilder(context, progress),
                  ),
                ),
                _verticalDrawer(reserved),
              ],
            ),
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
        child: widget.drawer,
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
        child: widget.drawer,
      ),
    ),
  );
}
