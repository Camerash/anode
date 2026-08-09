import 'package:anode/interface/button_actuation_feedback.dart';
import 'package:anode/interface/interface_audio_mixer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preferences gate audio and haptic outputs', () {
    var soundEnabled = false;
    var hapticsEnabled = false;
    var hapticCount = 0;
    final down = _RecordingAudioCue();
    final up = _RecordingAudioCue();
    final feedback = ConfiguredButtonActuationFeedback(
      soundEnabled: () => soundEnabled,
      hapticsEnabled: () => hapticsEnabled,
      downCue: down,
      upCue: up,
      haptic: () async => hapticCount++,
    );

    feedback.beginPress().release();
    feedback.activate();
    expect(down.plays, 0);
    expect(up.plays, 0);
    expect(hapticCount, 0);

    soundEnabled = true;
    hapticsEnabled = true;
    feedback.beginPress().release();
    feedback.activate();
    expect(down.plays, 1);
    expect(up.plays, 1);
    expect(hapticCount, 1);
  });

  test('release is idempotent and preserves its press decision', () {
    var soundEnabled = true;
    final down = _RecordingAudioCue();
    final up = _RecordingAudioCue();
    final feedback = ConfiguredButtonActuationFeedback(
      soundEnabled: () => soundEnabled,
      hapticsEnabled: () => false,
      downCue: down,
      upCue: up,
    );

    final session = feedback.beginPress();
    soundEnabled = false;
    session
      ..release()
      ..release();
    expect(down.plays, 1);
    expect(up.plays, 1);
  });

  test('rapid sessions can overlap without losing either phase', () {
    final down = _RecordingAudioCue();
    final up = _RecordingAudioCue();
    final feedback = ConfiguredButtonActuationFeedback(
      soundEnabled: () => true,
      hapticsEnabled: () => false,
      downCue: down,
      upCue: up,
    );

    final sessions = List.generate(32, (_) => feedback.beginPress());
    for (final session in sessions.reversed) {
      session.release();
    }
    expect(down.plays, 32);
    expect(up.plays, 32);
  });

  test('profile loads one mixer source for each actuation phase', () async {
    final mixer = _RecordingAudioMixer();
    final feedback = await ConfiguredButtonActuationFeedback.load(
      profile: const ButtonActuationProfile(
        downAsset: 'down.wav',
        downVolume: 0.8,
        upAsset: 'up.wav',
        upVolume: 0.6,
      ),
      mixer: mixer,
      soundEnabled: () => true,
      hapticsEnabled: () => false,
    );

    expect(mixer.loads, const [('down.wav', 0.8), ('up.wav', 0.6)]);
    feedback.beginPress().release();
    expect(mixer.cues[0].plays, 1);
    expect(mixer.cues[1].plays, 1);

    await feedback.dispose();
    expect(mixer.cues.every((cue) => cue.disposed), isTrue);
  });

  test('audio failure does not block actuation or haptic output', () {
    var hapticCount = 0;
    final feedback = ConfiguredButtonActuationFeedback(
      soundEnabled: () => true,
      hapticsEnabled: () => true,
      downCue: _ThrowingAudioCue(),
      upCue: _ThrowingAudioCue(),
      haptic: () async => hapticCount++,
    );

    expect(() => feedback.beginPress().release(), returnsNormally);
    expect(() => feedback.activate(), returnsNormally);
    expect(hapticCount, 1);
  });
}

class _RecordingAudioCue implements InterfaceAudioCue {
  int plays = 0;
  bool disposed = false;

  @override
  void play() => plays++;

  @override
  Future<void> dispose() async => disposed = true;
}

class _RecordingAudioMixer implements InterfaceAudioMixer {
  final loads = <(String, double)>[];
  final cues = <_RecordingAudioCue>[];

  @override
  Future<InterfaceAudioCue> loadCue({
    required String asset,
    required double volume,
  }) async {
    loads.add((asset, volume));
    final cue = _RecordingAudioCue();
    cues.add(cue);
    return cue;
  }

  @override
  Future<void> dispose() async {}
}

class _ThrowingAudioCue implements InterfaceAudioCue {
  @override
  void play() => throw StateError('audio unavailable');

  @override
  Future<void> dispose() async {}
}
