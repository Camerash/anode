import 'package:flutter/widgets.dart';
import 'package:native_device_orientation/native_device_orientation.dart';

/// Physical interface direction, kept independent of plugin types so layout
/// code and tests stay deterministic.
enum PhysicalInterfaceOrientation {
  portraitUp,
  portraitDown,
  landscapeLeft,
  landscapeRight,
  unknown;

  factory PhysicalInterfaceOrientation.fromNative(
    NativeDeviceOrientation orientation,
  ) => switch (orientation) {
    NativeDeviceOrientation.portraitUp => portraitUp,
    NativeDeviceOrientation.portraitDown => portraitDown,
    NativeDeviceOrientation.landscapeLeft => landscapeLeft,
    NativeDeviceOrientation.landscapeRight => landscapeRight,
    NativeDeviceOrientation.unknown => unknown,
  };
}

typedef PhysicalInterfaceOrientationBuilder =
    Widget Function(BuildContext context, PhysicalInterfaceOrientation value);

/// Reads platform UI orientation only; physical sensors remain disabled.
///
/// Mount this around routes that need left/right landscape direction so the
/// native listener has the same lifetime as that route.
class PhysicalInterfaceOrientationReader extends StatelessWidget {
  const PhysicalInterfaceOrientationReader({super.key, required this.builder});

  final PhysicalInterfaceOrientationBuilder builder;

  @override
  Widget build(BuildContext context) => NativeDeviceOrientationReader(
    useSensor: false,
    builder: (context) => builder(
      context,
      PhysicalInterfaceOrientation.fromNative(
        NativeDeviceOrientationReader.orientation(context),
      ),
    ),
  );
}
