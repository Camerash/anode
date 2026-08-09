import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

const interfaceAudioSessionConfiguration = AudioSessionConfiguration(
  avAudioSessionCategory: AVAudioSessionCategory.ambient,
  avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.mixWithOthers,
  avAudioSessionMode: AVAudioSessionMode.defaultMode,
  avAudioSessionSetActiveOptions:
      AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
  androidAudioAttributes: AndroidAudioAttributes(
    contentType: AndroidAudioContentType.sonification,
    usage: AndroidAudioUsage.assistanceSonification,
  ),
  androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransientMayDuck,
  androidWillPauseWhenDucked: false,
);

abstract interface class InterfaceAudioCue {
  void play();

  Future<void> dispose();
}

abstract interface class InterfaceAudioMixer {
  Future<InterfaceAudioCue> loadCue({
    required String asset,
    required double volume,
  });

  Future<void> dispose();
}

/// One low-latency mixer shared by all controls in the active interface skin.
final class SoLoudInterfaceAudioMixer implements InterfaceAudioMixer {
  SoLoudInterfaceAudioMixer._({
    required SoLoud engine,
    required AudioSession session,
  }) : _engine = engine,
       _session = session;

  static const _sampleRate = 48000;
  static const _bufferSize = 512;
  static const _maxActiveVoices = 16;

  final SoLoud _engine;
  final AudioSession _session;
  bool _disposed = false;

  static bool get _usesIosAudioSession =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<SoLoudInterfaceAudioMixer?> initialize() async {
    AudioSession? session;
    var iosSessionActive = false;
    try {
      session = await AudioSession.instance;
      await session.configure(interfaceAudioSessionConfiguration);
      if (_usesIosAudioSession) {
        iosSessionActive = await session.setActive(true);
        if (!iosSessionActive) {
          throw StateError('iOS audio session activation was denied');
        }
      }

      final engine = SoLoud.instance;
      await engine.init(
        sampleRate: _sampleRate,
        bufferSize: _bufferSize,
        channels: Channels.stereo,
        lowLatency: true,
      );
      engine.setMaxActiveVoiceCount(_maxActiveVoices);
      return SoLoudInterfaceAudioMixer._(engine: engine, session: session);
    } catch (error) {
      debugPrint('Interface audio initialization failed: $error');
      if (SoLoud.instance.isInitialized) {
        await SoLoud.instance.deinitAsync();
      }
      if (iosSessionActive) {
        await session?.setActive(false);
      }
      return null;
    }
  }

  @override
  Future<InterfaceAudioCue> loadCue({
    required String asset,
    required double volume,
  }) async {
    if (_disposed) throw StateError('Interface audio mixer is disposed');
    final data = await rootBundle.load(asset);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final source = await _engine.loadMem(asset, bytes, mode: LoadMode.memory);
    return _SoLoudInterfaceAudioCue(
      engine: _engine,
      source: source,
      volume: volume,
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _engine.deinitAsync();
    if (_usesIosAudioSession) {
      await _session.setActive(false);
    }
  }
}

final class _SoLoudInterfaceAudioCue implements InterfaceAudioCue {
  _SoLoudInterfaceAudioCue({
    required SoLoud engine,
    required AudioSource source,
    required this.volume,
  }) : _engine = engine,
       _source = source;

  final SoLoud _engine;
  final AudioSource _source;
  final double volume;
  bool _disposed = false;

  @override
  void play() {
    if (_disposed) return;
    _engine.play(_source, volume: volume);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (_engine.isInitialized) await _engine.disposeSource(_source);
  }
}
