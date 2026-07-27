import 'component_instance.dart';
import 'placement.dart';
import 'settings.dart';

/// Read-only shape shared by immutable presets and user-owned dashboards.
///
/// Rendering and activation consume this interface so activating a preset does
/// not silently fork it into a dashboard.
abstract interface class Design {
  String get id;
  String get name;
  Set<DesignOrientation> get supportedOrientations;
  List<ComponentInstance> get components;
  DashboardSettings get renderSettings;

  bool supports(DesignOrientation orientation);
  double frameAspect(DesignOrientation orientation);
  List<ComponentInstance> componentsIn(DesignOrientation orientation);
}
