import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'mechanical_feedback.dart';

/// Two fixed-footprint control faces separated by a top-hinged fascia.
///
/// The service face never changes parent layout. Opening rotates only the
/// fascia; controls behind it hard-enable after the mechanism seats.
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
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 150),
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
        duration: const Duration(milliseconds: 150),
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
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final open = widget.open;
          final servicePainted = open || _controller.value > 0;
          final serviceSeated = open && _controller.value == 1;
          final frontSeated = !open && _controller.value == 0;
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Offstage(
                offstage: !servicePainted,
                child: IgnorePointer(
                  ignoring: !serviceSeated,
                  child: ExcludeSemantics(
                    excluding: !serviceSeated,
                    child: KeyedSubtree(
                      key: const ValueKey('service-hatch-inside'),
                      child: widget.service,
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                ignoring: !frontSeated,
                child: ExcludeSemantics(
                  excluding: !frontSeated,
                  child: Transform(
                    alignment: Alignment.topCenter,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0015)
                      ..rotateX(-math.pi * 0.5 * _controller.value),
                    child: KeyedSubtree(
                      key: const ValueKey('service-hatch-front'),
                      child: widget.front,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
