import 'package:flutter/widgets.dart';

import 'vfd/vfd_cluster.dart';
import 'vfd/vfd_layers.dart';
import 'vfd/vfd_widgets.dart';

/// Runtime controls, docked in the dead space the contain-fit leaves below the
/// design band. The dock's height is reserved out of the cluster's safe rect, so
/// growing it shrinks the band uniformly — it never reflows it.
///
/// Drawn in the VFD idiom: etched controls on the substrate, no panel fill.
class VfdDock extends StatefulWidget {
  const VfdDock({
    super.key,
    required this.controller,
    required this.autoDrive,
    required this.manualKph,
    required this.onAutoDriveChanged,
    required this.onManualKphChanged,
    required this.onUnitChanged,
    required this.onPhosphorChanged,
    required this.onOpenLibrary,
    required this.onLayersChanged,
  });

  /// Height of the controls themselves, excluding the system inset below them.
  static const double height = 104;

  final VfdController controller;
  final bool autoDrive;
  final double manualKph;
  final ValueChanged<bool> onAutoDriveChanged;
  final ValueChanged<double> onManualKphChanged;
  final ValueChanged<SpeedUnit> onUnitChanged;
  final ValueChanged<Phosphor> onPhosphorChanged;
  final VoidCallback onOpenLibrary;
  final ValueChanged<VfdLayers> onLayersChanged;

  @override
  State<VfdDock> createState() => _VfdDockState();
}

class _VfdDockState extends State<VfdDock> {
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final palette = VfdPalette.of(controller.phosphor);

    return SizedBox(
      height: VfdDock.height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              height: 44,
              child: Row(
                children: <Widget>[
                  VfdButton(
                    label: widget.autoDrive ? 'HOLD' : 'RUN',
                    palette: palette,
                    lit: widget.autoDrive,
                    onTap: () => widget.onAutoDriveChanged(!widget.autoDrive),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: VfdCellBar(
                      value: widget.manualKph,
                      min: 0,
                      max: 260,
                      palette: palette,
                      onChanged: widget.onManualKphChanged,
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 68,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: VfdLegend(
                        '${controller.displaySpeed.round()} ${controller.unit.label}',
                        palette: palette,
                        lit: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: <Widget>[
                    _slot(VfdButton(
                      label: 'LIBRARY',
                      palette: palette,
                      onTap: widget.onOpenLibrary,
                    )),
                    _slot(VfdRule(palette: palette)),
                    for (final u in SpeedUnit.values)
                      _slot(VfdButton(
                        label: u.label,
                        palette: palette,
                        lit: controller.unit == u,
                        onTap: () => widget.onUnitChanged(u),
                      )),
                    _slot(VfdRule(palette: palette)),
                    for (final p in Phosphor.all)
                      _slot(VfdButton(
                        label: p.name,
                        palette: palette,
                        lit: controller.phosphor == p,
                        onTap: () => widget.onPhosphorChanged(p),
                      )),
                    _slot(VfdRule(palette: palette)),
                    for (final key in VfdLayers.keys)
                      _slot(VfdButton(
                        label: VfdLayers.labels[key]!,
                        palette: palette,
                        lit: controller.layers[key],
                        onTap: () {
                          final layers = controller.layers
                              .withKey(key, !controller.layers[key]);
                          setState(() => controller.layers = layers);
                          widget.onLayersChanged(layers);
                        },
                      )),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slot(Widget child) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Center(child: child),
      );
}
