# Anode

A GPS speedometer that simulates a 1980s vacuum fluorescent display at the
optical level. Read `CLAUDE.md` before changing the renderer — it records why
things are the way they are.

## Running it

```
flutter create . --project-name anode --platforms=ios,android
flutter pub get
flutter run
```

The first command generates the platform folders around the existing `lib/`,
`shaders/` and `pubspec.yaml`. It will not overwrite them. Answer no if it
offers to replace `pubspec.yaml` or `lib/main.dart`.

`lib/main.dart` is a workbench, not the product: a simulated speed source, every
layer toggle, and the three phosphor colours. Use it to tune the render. The
real app screen comes later.

Pointer position over the cluster drives tilt on desktop. On device, wire
`TiltSource.ingestGravity` to `sensors_plus`.

## Dependency versions

The version constraints in `pubspec.yaml` were written against packages current
in mid-2026 and may be stale. Run `flutter pub outdated` before doing anything
else, and verify the `geolocator` API surface against its current docs rather
than assuming — `GpsSpeedSource.start` is deliberately left unimplemented for
this reason.

## What is where

```
shaders/vfd.frag          the render, and the product
lib/vfd/vfd_cluster.dart  controller, painter, widget
lib/vfd/vfd_layers.dart   layer toggles and phosphor definitions
lib/vfd/speed_source.dart GPS + simulated speed, Kalman filter, tilt smoothing
lib/main.dart             workbench harness
```

Nothing outside `lib/vfd/` should know that a `FragmentShader` exists. That
boundary is what makes a future backend swap an afternoon instead of a rewrite.

## Profiling

Never trust the simulator for this. Measure with `flutter run --profile` on a
physical device, screen at full brightness, GPS active, phone warm. Thermals
matter more than framerate.
