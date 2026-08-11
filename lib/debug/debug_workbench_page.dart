import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../model/component_type.dart';
import '../model/dashboard.dart';
import '../model/design_preset.dart';
import '../vfd/prism_widgets.dart';
import '../vfd/speed_source.dart';
import '../vfd/vfd_cluster.dart';
import '../vfd/vfd_render_assets.dart';
import '../vfd/vfd_types.dart';
import '../vfd/vfd_widgets.dart';

class DebugWorkbenchPage extends StatefulWidget {
  const DebugWorkbenchPage({
    super.key,
    required this.state,
    required this.renderAssets,
  });

  final AnodeState state;
  final VfdRenderAssets renderAssets;

  @override
  State<DebugWorkbenchPage> createState() => _DebugWorkbenchPageState();
}

class _DebugWorkbenchPageState extends State<DebugWorkbenchPage>
    with SingleTickerProviderStateMixin {
  late Dashboard _design = _debugSnapshot();
  late final VfdController _controller = VfdController(
    vsync: this,
    design: _design,
    viewportSize: const Size(2.6, 1),
  );
  final SimulatedSpeedSource _simulated = SimulatedSpeedSource();
  StreamSubscription<double>? _subscription;
  bool _running = true;
  double _manualKph = 95;

  @override
  void initState() {
    super.initState();
    _subscription = _simulated.kph.listen((value) {
      if (_running) _controller.speedKph = value;
    });
    _controller.speedKph = _manualKph;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _simulated.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    assert(kDebugMode);
    final palette = VfdPalette.of(_controller.phosphor);
    final style = _design.settings.prismStyle;
    return ColoredBox(
      color: const Color(0xFF000000),
      child: SafeArea(
        child: Column(
          children: <Widget>[
            SizedBox(
              height: 48,
              child: PrismPanel(
                palette: palette,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  children: <Widget>[
                    PrismButton(
                      label: 'Back',
                      palette: palette,
                      role: PrismRole.compact,
                      style: style,
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: VfdLegend(
                        'Debug bench',
                        palette: palette,
                        lit: true,
                        size: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: VfdCluster(
                renderAssets: widget.renderAssets,
                controller: _controller,
                frameInsets: EdgeInsets.zero,
              ),
            ),
            SizedBox(
              height: 116,
              child: PrismPanel(
                palette: palette,
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: <Widget>[
                    PrismButton(
                      label: 'Run',
                      palette: palette,
                      lit: _running,
                      role: PrismRole.standard,
                      style: style,
                      onPressed: () => setState(() => _running = !_running),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: VfdCellBar(
                        value: _manualKph,
                        min: 0,
                        max: 260,
                        palette: palette,
                        cells: 32,
                        step: 1,
                        precision: 0,
                        semanticLabel: 'Manual speed',
                        onChanged: (value) => setState(() {
                          _running = false;
                          _manualKph = value;
                          _controller.speedKph = value;
                        }),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PrismButton(
                      label: 'KM/H',
                      palette: palette,
                      lit: _controller.unit == SpeedUnit.kph,
                      role: PrismRole.compact,
                      style: style,
                      onPressed: () => _setUnit('kph'),
                    ),
                    const SizedBox(width: 4),
                    PrismButton(
                      label: 'MPH',
                      palette: palette,
                      lit: _controller.unit == SpeedUnit.mph,
                      role: PrismRole.compact,
                      style: style,
                      onPressed: () => _setUnit('mph'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Dashboard _debugSnapshot() => switch (widget.state.activeDesign) {
    DesignPreset preset => Dashboard.forkFrom(
      preset,
      id: 'debug.preview',
      name: preset.name,
    ),
    Dashboard dashboard => Dashboard.cloneFrom(
      dashboard,
      id: 'debug.preview',
      name: dashboard.name,
    ),
    _ => throw StateError('Unsupported design'),
  };

  void _setUnit(String nextUnit) {
    if ((_controller.unit == SpeedUnit.kph ? 'kph' : 'mph') == nextUnit) {
      return;
    }
    var next = _design;
    for (final component in _design.components) {
      if (component.typeId == ComponentTypes.speedDigits) {
        next = next.withComponent(component.withParam('unit', nextUnit));
      }
    }
    setState(() {
      _design = next;
      _controller.design = next;
    });
  }
}
