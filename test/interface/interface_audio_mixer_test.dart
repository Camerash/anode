import 'package:anode/interface/interface_audio_mixer.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('interface audio session uses non-interrupting UI sound policy', () {
    final configuration = interfaceAudioSessionConfiguration;

    expect(
      configuration.avAudioSessionCategory,
      AVAudioSessionCategory.ambient,
    );
    expect(
      configuration.avAudioSessionCategoryOptions?.contains(
        AVAudioSessionCategoryOptions.mixWithOthers,
      ),
      isTrue,
    );
    expect(
      configuration.androidAudioAttributes?.contentType,
      AndroidAudioContentType.sonification,
    );
    expect(
      configuration.androidAudioAttributes?.usage,
      AndroidAudioUsage.assistanceSonification,
    );
    expect(configuration.androidWillPauseWhenDucked, isFalse);
  });
}
