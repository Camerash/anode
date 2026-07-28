import 'dart:async';
import 'dart:math' as math;

abstract class SpeedSource {
  Stream<double> get kph;
  Future<void> dispose();
}

class SpeedFilter {
  SpeedFilter({this.processNoise = 0.6});

  final double processNoise;
  double _x = 0;
  double _p = 1;
  bool _seeded = false;

  double get value => _x;

  double update(double measurementKph, double measurementNoise, double dt) {
    if (!_seeded) {
      _x = measurementKph;
      _seeded = true;
      return _x;
    }
    _p += processNoise * dt;
    final r = math.max(measurementNoise, 0.5);
    final k = _p / (_p + r);
    _x += k * (measurementKph - _x);
    _p *= (1 - k);
    return _x;
  }
}

class SimulatedSpeedSource implements SpeedSource {
  SimulatedSpeedSource() {
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final t = _sw.elapsedMilliseconds / 1000.0;
      final v =
          100 +
          70 * math.sin(t * 0.21) +
          26 * math.sin(t * 0.63 + 1.3) +
          11 * math.sin(t * 1.45);
      _out.add(v.clamp(0.0, 260.0));
    });
  }

  final _out = StreamController<double>.broadcast();
  final _sw = Stopwatch()..start();
  late final Timer _timer;

  @override
  Stream<double> get kph => _out.stream;

  @override
  Future<void> dispose() async {
    _timer.cancel();
    await _out.close();
  }
}

class GpsSpeedSource implements SpeedSource {
  GpsSpeedSource();

  final _out = StreamController<double>.broadcast();
  final _filter = SpeedFilter();
  StreamSubscription<dynamic>? _sub;
  DateTime? _lastFix;

  Future<void> start() async {
    throw UnimplementedError(
      'Wire this to geolocator: request permission, then subscribe to '
      'Geolocator.getPositionStream with LocationAccuracy.bestForNavigation. '
      'Feed position.speed (m/s, convert to kph) and position.speedAccuracy '
      'into ingest(). Verify the geolocator API surface against the current '
      'package version before writing this.',
    );
  }

  void ingest(double speedMetersPerSecond, double speedAccuracyMps) {
    final now = DateTime.now();
    final dt = _lastFix == null
        ? 0.1
        : now.difference(_lastFix!).inMilliseconds / 1000.0;
    _lastFix = now;
    final kphValue = speedMetersPerSecond * 3.6;
    final noise = (speedAccuracyMps.isFinite && speedAccuracyMps > 0)
        ? speedAccuracyMps * 3.6
        : 4.0;
    _out.add(_filter.update(kphValue, noise, dt).clamp(0.0, 400.0));
  }

  @override
  Stream<double> get kph => _out.stream;

  @override
  Future<void> dispose() async {
    await _sub?.cancel();
    await _out.close();
  }
}

class TiltSource {
  TiltSource({this.deadzone = 0.04, this.smoothing = 0.12});

  final double deadzone;
  final double smoothing;
  double _value = 0;

  double get value => _value;

  void ingestGravity(double gx, double gy, double gz) {
    final magnitude = math.sqrt(gx * gx + gy * gy + gz * gz);
    if (magnitude < 0.1) return;
    var raw = (gx / magnitude).clamp(-1.0, 1.0);
    if (raw.abs() < deadzone) {
      raw = 0.0;
    } else {
      raw = (raw.abs() - deadzone) / (1 - deadzone) * raw.sign;
    }
    _value += (raw - _value) * smoothing;
  }
}
