import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../actions/action_registry.dart';
import '../model/component_instance.dart';
import '../model/design.dart';
import 'vfd_cluster.dart';

/// Non-painting hit regions for explicit interactive design components.
///
/// Visuals remain in the one shared shader pass. These regions provide input
/// and semantics only, so they cannot introduce halo seams.
class DesignActionOverlay extends StatelessWidget {
  const DesignActionOverlay({
    super.key,
    required this.design,
    required this.layoutId,
    required this.controller,
    required this.registry,
    this.frameInsets = EdgeInsets.zero,
  });

  final Design design;
  final String layoutId;
  final VfdController controller;
  final ActionRegistry registry;
  final EdgeInsets frameInsets;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      final frameRect = Rect.fromLTRB(
        frameInsets.left,
        frameInsets.top,
        size.width - frameInsets.right,
        size.height - frameInsets.bottom,
      );
      final frame = design.frameExtent(layoutId);
      final fitScale = math.min(
        frameRect.width / frame.width,
        frameRect.height / frame.height,
      );
      final frameCenter = frameRect.center;
      return Stack(
        children: <Widget>[
          for (final component in design.componentsIn(layoutId))
            if (component.actionBinding != null)
              _hitRegion(component, frame, fitScale, frameCenter),
        ],
      );
    },
  );

  Widget _hitRegion(
    ComponentInstance component,
    Size frame,
    double scale,
    Offset frameCenter,
  ) {
    final placement = component.placements[layoutId]!;
    final center = placement.center;
    final extent = placement.size;
    final binding = component.actionBinding!;
    final action = registry[binding.actionId];
    final enabled = action?.available ?? false;
    return Positioned(
      left: frameCenter.dx + (center.dx - extent.width / 2) * scale,
      top: frameCenter.dy - (center.dy + extent.height / 2) * scale,
      width: extent.width * scale,
      height: extent.height * scale,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: action?.spec.label ?? 'Unavailable action',
        hint: enabled ? action?.spec.description : action?.unavailableReason,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled
              ? (_) => controller.setComponentPressed(component.id, true)
              : null,
          onTapCancel: enabled
              ? () => controller.setComponentPressed(component.id, false)
              : null,
          onTapUp: enabled
              ? (_) => controller.setComponentPressed(component.id, false)
              : null,
          onTap: enabled ? () => registry.invoke(binding) : null,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}
