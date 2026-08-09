import '../interface/button_actuation_feedback.dart';

/// Interaction feedback assets owned by the VFD interface skin.
abstract final class VfdInterfaceFeedback {
  static const buttonActuation = ButtonActuationProfile(
    downAsset: 'assets/audio/interface/vfd/button_down.wav',
    upAsset: 'assets/audio/interface/vfd/button_up.wav',
  );
}
