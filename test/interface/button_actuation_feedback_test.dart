import 'package:anode/interface/button_actuation_feedback.dart';
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

    final first = feedback.beginPress();
    final second = feedback.beginPress();
    second.release();
    first.release();
    expect(down.plays, 2);
    expect(up.plays, 2);
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

class _RecordingAudioCue implements ButtonAudioCue {
  int plays = 0;

  @override
  void play() => plays++;

  @override
  Future<void> dispose() async {}
}

class _ThrowingAudioCue implements ButtonAudioCue {
  @override
  void play() => throw StateError('audio unavailable');

  @override
  Future<void> dispose() async {}
}
