import 'package:flutter/widgets.dart';

import 'editor/effect_panel.dart';
import 'model/optical_profile.dart';
import 'model/settings.dart';
import 'vfd/prism_widgets.dart';
import 'vfd/vfd_cluster.dart';
import 'vfd/vfd_types.dart';
import 'vfd/vfd_widgets.dart';

/// Runtime control panel. Its extent is removed from the safe rect, so opening
/// it contain-scales the authored frame rather than reflowing components.
class VfdDock extends StatelessWidget {
  const VfdDock({
    super.key,
    required this.controller,
    required this.settings,
    required this.preferences,
    required this.editable,
    required this.autoDrive,
    required this.manualKph,
    required this.onAutoDriveChanged,
    required this.onManualKphChanged,
    required this.onUnitChanged,
    required this.onOpenLibrary,
    required this.onCustomize,
    required this.onProfileChanged,
  });

  static const double height = 264;

  final VfdController controller;
  final DashboardSettings settings;
  final GlobalSettings preferences;
  final bool editable;
  final bool autoDrive;
  final double manualKph;
  final ValueChanged<bool> onAutoDriveChanged;
  final ValueChanged<double> onManualKphChanged;
  final ValueChanged<SpeedUnit> onUnitChanged;
  final VoidCallback onOpenLibrary;
  final VoidCallback onCustomize;
  final ValueChanged<OpticalProfile> onProfileChanged;

  @override
  Widget build(BuildContext context) {
    final palette = VfdPalette.of(settings.opticalProfile.phosphor);
    return SizedBox(
      height: height,
      child: Column(
        children: <Widget>[
          SizedBox(
            height: 54,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              child: Row(
                children: <Widget>[
                  PrismButton(
                    label: autoDrive ? 'Hold' : 'Run',
                    palette: palette,
                    lit: autoDrive,
                    role: PrismRole.compact,
                    span: PrismSpan.one,
                    style: settings.prismStyle,
                    soundEnabled: preferences.soundEnabled,
                    hapticsEnabled: preferences.hapticsEnabled,
                    onPressed: () => onAutoDriveChanged(!autoDrive),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: VfdCellBar(
                      value: manualKph,
                      min: 0,
                      max: 260,
                      palette: palette,
                      onChanged: onManualKphChanged,
                    ),
                  ),
                  const SizedBox(width: 8),
                  for (final unit in SpeedUnit.values) ...<Widget>[
                    PrismButton(
                      label: unit.label,
                      palette: palette,
                      lit: controller.unit == unit,
                      enabled: editable,
                      role: PrismRole.compact,
                      span: PrismSpan.one,
                      style: settings.prismStyle,
                      soundEnabled: preferences.soundEnabled,
                      hapticsEnabled: preferences.hapticsEnabled,
                      onPressed: editable ? () => onUnitChanged(unit) : null,
                    ),
                    const SizedBox(width: 6),
                  ],
                  PrismButton(
                    label: 'Library',
                    palette: palette,
                    role: PrismRole.compact,
                    span: PrismSpan.one,
                    style: settings.prismStyle,
                    soundEnabled: preferences.soundEnabled,
                    hapticsEnabled: preferences.hapticsEnabled,
                    onPressed: onOpenLibrary,
                  ),
                  if (!editable) ...<Widget>[
                    const SizedBox(width: 6),
                    PrismButton(
                      label: 'Customize',
                      palette: palette,
                      lit: true,
                      role: PrismRole.compact,
                      span: PrismSpan.two,
                      style: settings.prismStyle,
                      soundEnabled: preferences.soundEnabled,
                      hapticsEnabled: preferences.hapticsEnabled,
                      onPressed: onCustomize,
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: EffectPanel(
              title: editable
                  ? 'Design effects'
                  : 'Design effects · Preset is read-only',
              dashboardProfile: settings.opticalProfile,
              baseProfile: settings.opticalProfile,
              scope: EffectScope.dashboard,
              prismStyle: settings.prismStyle,
              soundEnabled: preferences.soundEnabled,
              hapticsEnabled: preferences.hapticsEnabled,
              editable: editable,
              onProfileChanged: onProfileChanged,
            ),
          ),
        ],
      ),
    );
  }
}
