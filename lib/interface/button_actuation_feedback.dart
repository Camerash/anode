import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'interface_audio_mixer.dart';

/// Theme-owned audio data for one physical button mechanism.
@immutable
class ButtonActuationProfile {
  const ButtonActuationProfile({
    required this.downAsset,
    required this.upAsset,
    this.downVolume = 1,
    this.upVolume = 1,
  });

  final String downAsset;
  final double downVolume;
  final String upAsset;
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
  final InterfaceAudioCue? downCue;
  final InterfaceAudioCue? upCue;
  final Future<void> Function() _haptic;
  bool _disposed = false;

  static Future<ConfiguredButtonActuationFeedback> load({
    required ButtonActuationProfile profile,
    required InterfaceAudioMixer? mixer,
    required bool Function() soundEnabled,
    required bool Function() hapticsEnabled,
  }) async {
    InterfaceAudioCue? downCue;
    InterfaceAudioCue? upCue;
    try {
      downCue = await mixer?.loadCue(
        asset: profile.downAsset,
        volume: profile.downVolume,
      );
      upCue = await mixer?.loadCue(
        asset: profile.upAsset,
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

  void _playCue(InterfaceAudioCue? cue, {required String phase}) {
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
