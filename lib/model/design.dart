import 'component_instance.dart';
import 'placement.dart';
import 'settings.dart';
import 'vfd_module.dart';

/// Read-only shape shared by immutable presets and user-owned dashboards.
///
/// Rendering and activation consume this interface so activating a preset does
/// not silently fork it into a dashboard.
abstract interface class Design {
  String get id;
  String get name;
  DesignOrientation get primaryOrientation;
  Set<DesignOrientation> get authoredOrientations;
  List<ComponentInstance> get components;
  List<VfdModule> get modules;
  Map<DesignOrientation, FrameSpec> get frameSpecs;
  DashboardSettings get renderSettings;

  bool hasAuthoredLayout(DesignOrientation orientation);
  DesignOrientation layoutForViewport(DesignOrientation orientation);
  FrameSpec frameSpec(DesignOrientation orientation);
  double frameAspect(DesignOrientation orientation);
  List<ComponentInstance> componentsIn(DesignOrientation orientation);
  VfdModule moduleFor(ComponentInstance component);
}
