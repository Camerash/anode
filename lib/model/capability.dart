/// What a component type needs from the device.
///
/// The app takes the union across the ACTIVE dashboard and starts only those
/// sensors and requests only those permissions, so the barometer stays off for
/// a layout with no altimeter and network permission is never requested for a
/// layout with no weather gauge.
enum Capability {
  gps,
  accelerometer,
  barometer,
  network,
  battery,
  tripStorage,
  ambientLight,
  mediaControl;

  static Capability? byName(String name) {
    for (final c in Capability.values) {
      if (c.name == name) return c;
    }
    return null;
  }
}
