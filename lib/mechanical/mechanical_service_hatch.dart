import 'package:flutter/widgets.dart';

import 'mechanical_feedback.dart';

/// Two fixed-footprint control faces separated by a retracting service shutter.
///
/// The service face never changes parent layout. Opening retracts only the
/// shutter; controls behind it hard-enable after the mechanism seats.
class MechanicalServiceHatch extends StatefulWidget {
  const MechanicalServiceHatch({
    super.key,
    required this.open,
    required this.front,
    required this.service,
    this.soundEnabled = true,
    this.hapticsEnabled = true,
  });

  final bool open;
  final Widget front;
  final Widget service;
  final bool soundEnabled;
  final bool hapticsEnabled;

  @override
  State<MechanicalServiceHatch> createState() => _MechanicalServiceHatchState();
}

class _MechanicalServiceHatchState extends State<MechanicalServiceHatch>
    with SingleTickerProviderStateMixin {
  static const _release = Duration(milliseconds: 20);
  static const _travel = Duration(milliseconds: 110);
  static const _seat = Duration(milliseconds: 20);
  static final _duration = _release + _travel + _seat;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _duration,
    value: widget.open ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant MechanicalServiceHatch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.open == widget.open) return;
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduced) {
      _controller.value = widget.open ? 1 : 0;
    } else {
      _controller.animateTo(
        widget.open ? 1 : 0,
        duration: _duration,
        curve: Curves.linear,
      );
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
  Widget build(BuildContext context) => SizedBox.expand(
    key: const ValueKey('mechanical-service-hatch'),
    child: ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) => AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => _mechanism(constraints.maxHeight),
        ),
      ),
    ),
  );

  Widget _mechanism(double height) {
    final progress = _controller.value;
    final serviceSeated = widget.open && progress == 1;
    final frontSeated = !widget.open && progress == 0;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        _serviceFace(
          painted: widget.open || progress > 0,
          seated: serviceSeated,
        ),
        _shutter(
          offset: _shutterOffset(progress, height),
          released: progress > 0,
          seated: frontSeated,
        ),
        const IgnorePointer(child: CustomPaint(painter: _ServiceLipPainter())),
      ],
    );
  }

  Widget _serviceFace({required bool painted, required bool seated}) =>
      Offstage(
        offstage: !painted,
        child: IgnorePointer(
          ignoring: !seated,
          child: ExcludeSemantics(
            excluding: !seated,
            child: KeyedSubtree(
              key: const ValueKey('service-hatch-inside'),
              child: widget.service,
            ),
          ),
        ),
      );

  Widget _shutter({
    required double offset,
    required bool released,
    required bool seated,
  }) => IgnorePointer(
    ignoring: !seated,
    child: ExcludeSemantics(
      excluding: !seated,
      child: Transform.translate(
        key: const ValueKey('service-hatch-shutter'),
        offset: Offset(0, offset),
        child: CustomPaint(
          foregroundPainter: _ShutterEdgePainter(released: released),
          child: KeyedSubtree(
            key: const ValueKey('service-hatch-front'),
            child: widget.front,
          ),
        ),
      ),
    ),
  );

  static double _shutterOffset(double progress, double height) {
    final releaseFraction = _release.inMicroseconds / _duration.inMicroseconds;
    final travelEndFraction =
        (_release + _travel).inMicroseconds / _duration.inMicroseconds;
    if (progress <= releaseFraction) {
      return 2 * progress / releaseFraction;
    }
    if (progress >= travelEndFraction) return height + 6;
    final travelProgress =
        (progress - releaseFraction) / (travelEndFraction - releaseFraction);
    return 2 + (height + 4) * travelProgress;
  }
}

class _ShutterEdgePainter extends CustomPainter {
  const _ShutterEdgePainter({required this.released});

  final bool released;

  @override
  void paint(Canvas canvas, Size size) {
    if (!released) return;
    final shadow = Paint()
      ..color = const Color(0xB0000000)
      ..strokeWidth = 4;
    canvas.drawLine(Offset.zero, Offset(size.width, 0), shadow);
    canvas.drawLine(
      const Offset(2, 1),
      Offset(size.width - 2, 1),
      Paint()
        ..color = const Color(0xFF7A827E)
        ..strokeWidth = 0.7,
    );
  }

  @override
  bool shouldRepaint(covariant _ShutterEdgePainter oldDelegate) =>
      oldDelegate.released != released;
}

class _ServiceLipPainter extends CustomPainter {
  const _ServiceLipPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const lipHeight = 5.0;
    canvas.drawRect(
      Rect.fromLTWH(0, size.height - lipHeight, size.width, lipHeight),
      Paint()..color = const Color(0xFF070A09),
    );
    canvas.drawLine(
      Offset(0, size.height - lipHeight),
      Offset(size.width, size.height - lipHeight),
      Paint()
        ..color = const Color(0xFF65706B)
        ..strokeWidth = 0.7,
    );
  }

  @override
  bool shouldRepaint(covariant _ServiceLipPainter oldDelegate) => false;
}
