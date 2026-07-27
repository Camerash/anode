import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'vfd/speed_source.dart';
import 'vfd/vfd_cluster.dart';
import 'vfd/vfd_widgets.dart';
import 'vfd_dock.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await WakelockPlus.enable();
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
      home: ClusterPage(program: program),
    );
  }
}

class ClusterPage extends StatefulWidget {
  const ClusterPage({super.key, required this.program});

  final ui.FragmentProgram program;

  @override
  State<ClusterPage> createState() => _ClusterPageState();
}

class _ClusterPageState extends State<ClusterPage>
    with SingleTickerProviderStateMixin {
  late final VfdController _controller =
      VfdController(vsync: this, maxKph: 260);
  final SimulatedSpeedSource _sim = SimulatedSpeedSource();
  StreamSubscription<double>? _sub;
  bool _autoDrive = true;
  bool _dockOpen = false;
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

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion && _controller.layers.tiltParallax) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _controller.layers = _controller.layers.withKey('tiltParallax', false);
        });
      });
    }

    final windowPadding = MediaQuery.paddingOf(context);

    // Reserving the dock's height out of the safe rect is what keeps the band
    // honest: the contain-fit shrinks it uniformly and re-centres it, so the
    // aspect never changes and nothing reflows. The substrate still reaches
    // every edge behind the controls.
    final dockExtent =
        _dockOpen ? VfdDock.height + windowPadding.bottom : 0.0;
    final clusterInsets = windowPadding.copyWith(
      bottom: _dockOpen ? dockExtent : windowPadding.bottom,
    );

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Full bleed: the substrate reaches the fragment bounds.
          LayoutBuilder(
            builder: (context, constraints) {
              void drive(Offset local) {
                _controller.tiltTarget =
                    (local.dx / constraints.maxWidth - 0.5) * 2;
              }

              return Listener(
                // Hover for desktop, move for touch drag.
                onPointerHover: (e) => drive(e.localPosition),
                onPointerMove: (e) => drive(e.localPosition),
                child: VfdCluster(
                  program: widget.program,
                  controller: _controller,
                  safeInsets: clusterInsets,
                ),
              );
            },
          ),
          // Content insets to the safe area; the background does not.
          Padding(
            padding: clusterInsets,
            child: Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: VfdButton(
                  // Auto-hide after a few seconds is still to come.
                  label: 'SET',
                  palette: VfdPalette.of(_controller.phosphor),
                  lit: _dockOpen,
                  onTap: () => setState(() => _dockOpen = !_dockOpen),
                ),
              ),
            ),
          ),
          if (_dockOpen)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Padding(
                padding: EdgeInsets.only(bottom: windowPadding.bottom),
                child: VfdDock(
                  controller: _controller,
                  autoDrive: _autoDrive,
                  manualKph: _manualKph,
                  onAutoDriveChanged: (v) => setState(() => _autoDrive = v),
                  onManualKphChanged: (v) => setState(() {
                    _autoDrive = false;
                    _manualKph = v;
                    _controller.speedKph = v;
                  }),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
