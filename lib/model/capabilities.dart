import 'capability.dart';
import 'component_instance.dart';
import 'component_type.dart';
import 'dashboard.dart';
import 'design_preset.dart';
import 'placement.dart';

/// The union of what the given components need.
///
/// Pass [orientation] to scope it to one authored layout. That is the sharper
/// answer: a barometer gauge that only exists in the landscape layout should
/// not start the barometer while the device is in portrait.
///
/// Components with no placement in any supported orientation are absent from
/// the design and contribute nothing.
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
  }
  return out;
}

extension DashboardCapabilities on Dashboard {
  Set<Capability> capabilities({DesignOrientation? orientation}) =>
      requiredCapabilities(components, orientation: orientation);
}

extension DesignPresetCapabilities on DesignPreset {
  Set<Capability> capabilities({DesignOrientation? orientation}) =>
      requiredCapabilities(components, orientation: orientation);
}
