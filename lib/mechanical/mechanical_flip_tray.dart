import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../vfd/vfd_widgets.dart';
import 'mechanical_feedback.dart';

/// Fixed-height bay whose top-hinged fascia reveals indexed controls.
class MechanicalFlipTray extends StatefulWidget {
  const MechanicalFlipTray({
    super.key,
    required this.open,
    required this.height,
    required this.palette,
    required this.child,
    this.soundEnabled = true,
    this.hapticsEnabled = true,
  });

  final bool open;
  final double height;
  final VfdPalette palette;
  final Widget child;
  final bool soundEnabled;
  final bool hapticsEnabled;

  @override
  State<MechanicalFlipTray> createState() => _MechanicalFlipTrayState();
}

class _MechanicalFlipTrayState extends State<MechanicalFlipTray>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 150),
    value: widget.open ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant MechanicalFlipTray oldWidget) {
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
    key: const ValueKey('mechanical-flip-tray'),
    height: widget.height,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF030504),
        border: Border.all(color: widget.palette.unlit.withValues(alpha: 0.24)),
      ),
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => Transform(
            alignment: Alignment.topCenter,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.002)
              ..rotateX((1 - _controller.value) * -math.pi / 2),
            child: Opacity(opacity: _controller.value, child: child),
          ),
          child: IgnorePointer(ignoring: !widget.open, child: widget.child),
        ),
      ),
    ),
  );
}
