import 'package:flutter/widgets.dart';

import '../actions/action_registry.dart';
import '../model/component_instance.dart';
import '../model/component_type.dart';
import '../model/design.dart';
import '../model/placement.dart';
import 'vfd_cluster.dart';

/// Non-painting hit regions for explicit interactive design components.
///
/// Visuals remain in the one shared shader pass. These regions provide input
/// and semantics only, so they cannot introduce halo seams.
class DesignActionOverlay extends StatelessWidget {
  const DesignActionOverlay({
    super.key,
    required this.design,
    required this.orientation,
    required this.controller,
    required this.registry,
    required this.safeInsets,
  });

  final Design design;
  final DesignOrientation orientation;
  final VfdController controller;
  final ActionRegistry registry;
  final EdgeInsets safeInsets;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      final safeRect = Rect.fromLTRB(
        safeInsets.left,
        safeInsets.top,
        size.width - safeInsets.right,
        size.height - safeInsets.bottom,
      );
      final aspect = design.frameAspect(orientation);
      final fitScale = (safeRect.width / aspect).clamp(0.0, safeRect.height);
      final frameCenter = safeRect.center;
      return Stack(
        children: <Widget>[
          for (final component in design.componentsIn(orientation))
            if (component.actionBinding != null)
              _hitRegion(component, aspect, fitScale, frameCenter),
        ],
      );
    },
  );

  Widget _hitRegion(
    ComponentInstance component,
    double aspect,
    double scale,
    Offset frameCenter,
  ) {
    final placement = component.placements[orientation]!;
    final center = placement.resolve(aspect);
    final extent = placement.resolveSize(
      ComponentTypes.byId(component.typeId),
      variant: component.effectiveVariant,
    );
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
