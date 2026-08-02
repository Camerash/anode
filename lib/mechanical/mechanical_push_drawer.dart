import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../model/optical_profile.dart';
import '../vfd/prism_widgets.dart';
import '../vfd/vfd_widgets.dart';
import 'mechanical_feedback.dart';

enum MechanicalDrawerEdge { right, bottom }

typedef MechanicalDrawerContentBuilder =
    Widget Function(BuildContext context, double progress);

/// Service bay that physically consumes workspace while opening.
///
/// The child canvas receives the remaining constraints. Drawer contents retain
/// their full layout extent behind a clipping aperture during travel. Its
/// surface stays full-bleed; [chromeInsets] protect readable controls from
/// physical unsafe edges and persistent overlay bands.
class MechanicalPushDrawer extends StatefulWidget {
  const MechanicalPushDrawer({
    super.key,
    required this.open,
    required this.edge,
    required this.extent,
    required this.palette,
    required this.prismStyle,
    required this.onOpenChanged,
    required this.contentBuilder,
    required this.drawer,
    this.chromeInsets = EdgeInsets.zero,
    this.soundEnabled = true,
    this.hapticsEnabled = true,
  });

  final bool open;
  final MechanicalDrawerEdge edge;
  final double extent;
  final VfdPalette palette;
  final PrismStyle prismStyle;
  final ValueChanged<bool> onOpenChanged;
  final MechanicalDrawerContentBuilder contentBuilder;
  final Widget drawer;

  /// Workspace-local bounds reserved for safe, readable chrome.
  final EdgeInsets chromeInsets;
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
    child: Padding(
      padding: _drawerSafePadding,
      child: KeyedSubtree(
        key: const ValueKey('mechanical-drawer-safe-content'),
        child: widget.drawer,
      ),
    ),
  );

  EdgeInsets get _drawerSafePadding => switch (widget.edge) {
    MechanicalDrawerEdge.right => EdgeInsets.only(
      top: widget.chromeInsets.top,
      right: widget.chromeInsets.right,
      bottom: widget.chromeInsets.bottom,
    ),
    MechanicalDrawerEdge.bottom => EdgeInsets.fromLTRB(
      widget.chromeInsets.left,
      0,
      widget.chromeInsets.right,
      widget.chromeInsets.bottom,
    ),
  };

  Widget _latch(double reserved) {
    final right = widget.edge == MechanicalDrawerEdge.right;
    return Positioned(
      left: right ? null : widget.chromeInsets.left + 8,
      right: right ? math.max(reserved, widget.chromeInsets.right) : null,
      bottom: right ? null : math.max(reserved, widget.chromeInsets.bottom),
      top: right ? widget.chromeInsets.top + 22 : null,
      width: 52,
      height: 44,
      child: PrismButton(
        key: const ValueKey('mechanical-drawer-latch'),
        label: 'Panel',
        palette: widget.palette,
        lit: widget.open,
        selected: widget.open,
        role: PrismRole.compact,
        style: widget.prismStyle,
        // Drawer state change emits the single latch feedback event.
        soundEnabled: false,
        hapticsEnabled: false,
        onPressed: () => widget.onOpenChanged(!widget.open),
      ),
    );
  }
}
