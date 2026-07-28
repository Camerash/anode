import 'capability.dart';
import 'action_binding.dart';
import 'component_instance.dart';
import 'component_type.dart';
import 'dashboard.dart';
import 'design_preset.dart';
import 'placement.dart';

/// The union of what the given components need.
///
/// Pass [orientation] to scope it to one resolved authored layout.
///
/// Components with no placement in any authored layout are absent and
/// contribute nothing.
Set<Capability> requiredCapabilities(
  Iterable<ComponentInstance> components, {
  DesignOrientation? orientation,
}) {
  final out = <Capability>{};
  for (final c in components) {
    if (orientation != null && !c.appearsIn(orientation)) continue;
    if (orientation == null && c.placements.isEmpty) continue;
    final type = ComponentTypes.byId(c.typeId);
    if (type == null) continue;
    out.addAll(type.capabilities);
    final action = c.actionBinding;
    if (action != null) {
      out.addAll(ActionSpecs.byId(action.actionId)?.capabilities ?? const {});
    }
  }
  return out;
}

extension DashboardCapabilities on Dashboard {
  Set<Capability> capabilities({DesignOrientation? orientation}) =>
      requiredCapabilities(
        components,
        orientation: orientation == null
            ? null
            : layoutForViewport(orientation),
      );
}

extension DesignPresetCapabilities on DesignPreset {
  Set<Capability> capabilities({DesignOrientation? orientation}) =>
      requiredCapabilities(
        components,
        orientation: orientation == null
            ? null
            : layoutForViewport(orientation),
      );
}
