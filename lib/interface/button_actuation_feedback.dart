import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Theme-owned audio data for one physical button mechanism.
@immutable
class ButtonActuationProfile {
  const ButtonActuationProfile({
    required this.downAsset,
    required this.downDuration,
    required this.upAsset,
    required this.upDuration,
    this.downVolume = 1,
    this.upVolume = 1,
  });

  final String downAsset;
  final Duration downDuration;
  final double downVolume;
  final String upAsset;
  final Duration upDuration;
  final double upVolume;
}

abstract interface class ButtonPressSession {
  void release();
}

/// Input-phase feedback shared by theme-specific button widgets.
abstract interface class ButtonActuationFeedback {
  ButtonPressSession beginPress();

  void activate();

  Future<void> dispose();
}

abstract interface class ButtonAudioCue {
  void play();

  Future<void> dispose();
}

class ButtonFeedbackScope extends InheritedWidget {
  const ButtonFeedbackScope({
    super.key,
    required this.feedback,
    required super.child,
  });

  final ButtonActuationFeedback feedback;

  static ButtonActuationFeedback of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ButtonFeedbackScope>()
          ?.feedback ??
      SilentButtonActuationFeedback.instance;

  @override
  bool updateShouldNotify(ButtonFeedbackScope oldWidget) =>
      feedback != oldWidget.feedback;
}

class SilentButtonActuationFeedback implements ButtonActuationFeedback {
  const SilentButtonActuationFeedback._();

  static const instance = SilentButtonActuationFeedback._();

  @override
  ButtonPressSession beginPress() => _SilentButtonPressSession.instance;

  @override
  void activate() {}

  @override
  Future<void> dispose() async {}
}

class _SilentButtonPressSession implements ButtonPressSession {
  const _SilentButtonPressSession._();

  static const instance = _SilentButtonPressSession._();

  @override
  void release() {}
}

/// Preference-aware feedback composed with audio from the active skin.
class ConfiguredButtonActuationFeedback implements ButtonActuationFeedback {
  ConfiguredButtonActuationFeedback({
    required this.soundEnabled,
    required this.hapticsEnabled,
    this.downCue,
    this.upCue,
    Future<void> Function()? haptic,
  }) : _haptic = haptic ?? HapticFeedback.lightImpact;

  final bool Function() soundEnabled;
  final bool Function() hapticsEnabled;
  final ButtonAudioCue? downCue;
  final ButtonAudioCue? upCue;
  final Future<void> Function() _haptic;
  bool _disposed = false;

  static Future<ConfiguredButtonActuationFeedback> load({
    required ButtonActuationProfile profile,
    required bool Function() soundEnabled,
    required bool Function() hapticsEnabled,
  }) async {
    ButtonAudioCue? downCue;
    ButtonAudioCue? upCue;
    try {
      downCue = await _PooledButtonAudioCue.load(
        asset: profile.downAsset,
        duration: profile.downDuration,
        volume: profile.downVolume,
      );
      upCue = await _PooledButtonAudioCue.load(
        asset: profile.upAsset,
        duration: profile.upDuration,
        volume: profile.upVolume,
      );
    } catch (error) {
      debugPrint('Button audio initialization failed: $error');
      await downCue?.dispose();
      await upCue?.dispose();
      downCue = null;
      upCue = null;
    }
    return ConfiguredButtonActuationFeedback(
      soundEnabled: soundEnabled,
      hapticsEnabled: hapticsEnabled,
      downCue: downCue,
      upCue: upCue,
    );
  }

  @override
  ButtonPressSession beginPress() {
    final playSound = !_disposed && soundEnabled();
    if (playSound) _playCue(downCue, phase: 'press');
    return _ConfiguredButtonPressSession(this, playSound: playSound);
  }

  @override
  void activate() {
    if (!_disposed && hapticsEnabled()) unawaited(_haptic());
  }

  void _release({required bool playSound}) {
    if (playSound && !_disposed) _playCue(upCue, phase: 'release');
  }

  void _playCue(ButtonAudioCue? cue, {required String phase}) {
    try {
      cue?.play();
    } catch (error) {
      debugPrint('Button $phase audio playback failed: $error');
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await Future.wait<void>([
      if (downCue case final cue?) cue.dispose(),
      if (upCue case final cue?) cue.dispose(),
    ]);
  }
}

class _ConfiguredButtonPressSession implements ButtonPressSession {
  _ConfiguredButtonPressSession(this._feedback, {required this.playSound});

  final ConfiguredButtonActuationFeedback _feedback;
  final bool playSound;
  bool _released = false;

  @override
  void release() {
    if (_released) return;
    _released = true;
    _feedback._release(playSound: playSound);
  }
}

class _PooledButtonAudioCue implements ButtonAudioCue {
  _PooledButtonAudioCue._({
    required AudioPool pool,
    required this.duration,
    required this.volume,
  }) : _pool = pool;

  final AudioPool _pool;
  final Duration duration;
  final double volume;
  final Set<Timer> _cleanupTimers = <Timer>{};
  bool _disposed = false;

  static Future<_PooledButtonAudioCue> load({
    required String asset,
    required Duration duration,
    required double volume,
  }) async {
    final pool = await AudioPool.create(
      source: AssetSource(asset),
      minPlayers: 2,
      maxPlayers: 4,
      playerMode: PlayerMode.lowLatency,
      audioContext: AudioContext(
        android: const AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.assistanceSonification,
          audioFocus: AndroidAudioFocus.none,
        ),
        iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
      ),
    );
    return _PooledButtonAudioCue._(
      pool: pool,
      duration: duration,
      volume: volume,
    );
  }

  @override
  void play() {
    if (_disposed) return;
    unawaited(() async {
      try {
        final stop = await _pool.start(volume: volume);
        if (_disposed) {
          await stop();
          return;
        }
        late final Timer timer;
        timer = Timer(duration + const Duration(milliseconds: 24), () {
          _cleanupTimers.remove(timer);
          unawaited(
            stop().catchError((Object error, StackTrace stackTrace) {
              debugPrint('Button audio cleanup failed: $error');
            }),
          );
        });
        _cleanupTimers.add(timer);
      } catch (error) {
        debugPrint('Button audio playback failed: $error');
      }
    }());
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final timer in _cleanupTimers) {
      timer.cancel();
    }
    _cleanupTimers.clear();
    await _pool.dispose();
  }
}
