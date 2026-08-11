import 'capability.dart';
import 'action_binding.dart';
import 'component_instance.dart';
import 'component_type.dart';
import 'dashboard.dart';
import 'design_preset.dart';

/// The union of what the given components need.
///
/// Pass [layoutId] to scope it to one authored layout.
///
/// Components with no placement in any authored layout are absent and
/// contribute nothing.
Set<Capability> requiredCapabilities(
  Iterable<ComponentInstance> components, {
  String? layoutId,
}) {
  final out = <Capability>{};
  for (final c in components) {
    if (layoutId != null && !c.appearsIn(layoutId)) continue;
    if (layoutId == null && c.placements.isEmpty) continue;
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
  Set<Capability> capabilities({String? layoutId}) =>
      requiredCapabilities(components, layoutId: layoutId);
}

extension DesignPresetCapabilities on DesignPreset {
  Set<Capability> capabilities({String? layoutId}) =>
      requiredCapabilities(components, layoutId: layoutId);
}
