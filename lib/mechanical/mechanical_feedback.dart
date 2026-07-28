import 'package:flutter/services.dart';

/// Emits one mechanical event. Callers own event boundaries so dragging cannot
/// produce feedback continuously between detents.
void actuateMechanicalFeedback({
  required bool soundEnabled,
  required bool hapticsEnabled,
}) {
  if (soundEnabled) SystemSound.play(SystemSoundType.click);
  if (hapticsEnabled) HapticFeedback.lightImpact();
}
