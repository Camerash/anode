import '../interface/button_actuation_feedback.dart';

/// Interaction feedback assets owned by the VFD interface skin.
abstract final class VfdInterfaceFeedback {
  static const buttonActuation = ButtonActuationProfile(
    downAsset: 'audio/interface/vfd/button_down.wav',
    downDuration: Duration(milliseconds: 66),
    upAsset: 'audio/interface/vfd/button_up.wav',
    upDuration: Duration(milliseconds: 114),
  );
}
