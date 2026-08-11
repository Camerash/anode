import 'dart:ui' show Size;

import 'component_instance.dart';
import 'design_layout.dart';
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
  String get baseLayoutId;
  List<DesignLayout> get layouts;
  ScreenSetup get screenSetup;
  List<ComponentInstance> get components;
  List<VfdModule> get modules;
  DashboardSettings get renderSettings;

  VfdModule moduleFor(ComponentInstance component);
}

extension DesignGeometry on Design {
  DesignLayout layout(String id) =>
      designLayoutById(layouts, id, fallbackId: baseLayoutId);

  String layoutForViewport(Size viewport) {
    final lockedId = screenSetup.lockedLayoutId;
    if (screenSetup.behavior == ScreenBehavior.lock &&
        lockedId != null &&
        layouts.any((layout) => layout.id == lockedId)) {
      return lockedId;
    }
    return nearestLayoutId(layouts, viewport, fallbackId: baseLayoutId);
  }

  FrameSpec frameSpec(String layoutId) => layout(layoutId).frame;
  double frameAspect(String layoutId) => layout(layoutId).aspect;
  Size frameExtent(String layoutId) => layout(layoutId).frame.extent;

  List<ComponentInstance> componentsIn(String layoutId) =>
      components.where((component) => component.appearsIn(layoutId)).toList();
}
