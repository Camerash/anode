import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'vfd/speed_source.dart';
import 'vfd/vfd_cluster.dart';
import 'vfd/vfd_layers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final program = await ui.FragmentProgram.fromAsset('shaders/vfd.frag');
  runApp(AnodeApp(program: program));
}

class AnodeApp extends StatelessWidget {
  const AnodeApp({super.key, required this.program});

  final ui.FragmentProgram program;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anode',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: WorkbenchPage(program: program),
    );
  }
}

class WorkbenchPage extends StatefulWidget {
  const WorkbenchPage({super.key, required this.program});

  final ui.FragmentProgram program;

  @override
  State<WorkbenchPage> createState() => _WorkbenchPageState();
}

class _WorkbenchPageState extends State<WorkbenchPage>
    with SingleTickerProviderStateMixin {
  late final VfdController _controller =
      VfdController(vsync: this, maxKph: 260);
  final SimulatedSpeedSource _sim = SimulatedSpeedSource();
  StreamSubscription<double>? _sub;
  bool _autoDrive = true;
  double _manualKph = 95;

  @override
  void initState() {
    super.initState();
    _sub = _sim.kph.listen((v) {
      if (_autoDrive) _controller.speedKph = v;
    });
    _controller.speedKph = _manualKph;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sim.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _setLayers(VfdLayers next) {
    setState(() => _controller.layers = next);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion && _controller.layers.tiltParallax) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _setLayers(_controller.layers.withKey('tiltParallax', false));
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0B),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AspectRatio(
              aspectRatio: 2.6,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  void drive(Offset local) {
                    _controller.tiltTarget =
                        (local.dx / constraints.maxWidth - 0.5) * 2;
                  }

                  // Hover for desktop, move for touch drag.
                  return Listener(
                    onPointerHover: (e) => drive(e.localPosition),
                    onPointerMove: (e) => drive(e.localPosition),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: VfdCluster(
                        program: widget.program,
                        controller: _controller,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Text('Speed'),
                Expanded(
                  child: Slider(
                    value: _manualKph,
                    min: 0,
                    max: 260,
                    onChanged: (v) => setState(() {
                      _autoDrive = false;
                      _manualKph = v;
                      _controller.speedKph = v;
                    }),
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: Text('${_controller.speedKph.round()} kph',
                      textAlign: TextAlign.right),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: () => setState(() => _autoDrive = !_autoDrive),
                  child: Text(_autoDrive ? 'Pause drive' : 'Resume drive'),
                ),
                for (final p in Phosphor.all)
                  FilledButton.tonal(
                    onPressed: () => setState(() => _controller.phosphor = p),
                    child: Text(p.name),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            for (final key in VfdLayers.keys)
              SwitchListTile(
                dense: true,
                title: Text(VfdLayers.labels[key]!),
                value: _controller.layers[key],
                onChanged: (v) =>
                    _setLayers(_controller.layers.withKey(key, v)),
              ),
          ],
        ),
      ),
    );
  }
}
