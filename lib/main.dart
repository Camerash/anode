import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'actions/action_registry.dart';
import 'app_state.dart';
import 'data/design_repository.dart';
import 'debug/debug_workbench_page.dart';
import 'library/library_page.dart';
import 'mechanical/hard_cut_route.dart';
import 'model/dev_design.dart';
import 'model/placement.dart';
import 'vfd/speed_source.dart';
import 'vfd/design_action_overlay.dart';
import 'vfd/prism_widgets.dart';
import 'vfd/vfd_cluster.dart';
import 'vfd/vfd_render_assets.dart';
import 'vfd/vfd_widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await WakelockPlus.enable();
  final renderAssets = await VfdRenderAssets.load();
  final repository = DesignRepository(await SharedPreferences.getInstance());
  final state = AnodeState.load(
    repository: repository,
    presets: [developmentPreset()],
  );
  runApp(AnodeApp(renderAssets: renderAssets, state: state));
}

class AnodeApp extends StatefulWidget {
  const AnodeApp({super.key, required this.renderAssets, required this.state});

  final VfdRenderAssets renderAssets;
  final AnodeState state;

  @override
  State<AnodeApp> createState() => _AnodeAppState();
}

class _AnodeAppState extends State<AnodeApp> {
  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      color: const Color(0xFF000000),
      title: 'Anode',
      debugShowCheckedModeBanner: false,
      textStyle: const TextStyle(
        color: Color(0xFF7C8681),
        decoration: TextDecoration.none,
      ),
      pageRouteBuilder: hardCutPageRoute,
      home: ClusterPage(renderAssets: widget.renderAssets, state: widget.state),
      onGenerateRoute: (settings) {
        if (settings.name == '/library') {
          final initial = settings.arguments is LibrarySection
              ? settings.arguments! as LibrarySection
              : LibrarySection.templates;
          return hardCutRoute<void>(
            (_) => LibraryPage(
              state: widget.state,
              renderAssets: widget.renderAssets,
              initialSection: initial,
            ),
            settings: settings,
          );
        }
        if (settings.name == '/debug' && kDebugMode) {
          return hardCutRoute<void>(
            (_) => DebugWorkbenchPage(
              state: widget.state,
              renderAssets: widget.renderAssets,
            ),
            settings: settings,
          );
        }
        return null;
      },
    );
  }

  @override
  void dispose() {
    widget.state.dispose();
    widget.renderAssets.dispose();
    super.dispose();
  }
}

class ClusterPage extends StatefulWidget {
  const ClusterPage({
    super.key,
    required this.renderAssets,
    required this.state,
  });

  final VfdRenderAssets renderAssets;
  final AnodeState state;

  @override
  State<ClusterPage> createState() => _ClusterPageState();
}

class _ClusterPageState extends State<ClusterPage>
    with SingleTickerProviderStateMixin {
  late final VfdController _controller;
  final SimulatedSpeedSource _sim = SimulatedSpeedSource();
  StreamSubscription<double>? _sub;
  late final ActionRegistry _actions;

  @override
  void initState() {
    super.initState();
    _controller = VfdController(
      vsync: this,
      design: widget.state.activeDesign,
      orientation: DesignOrientation.landscape,
    );
    _syncAppState();
    _actions = ActionRegistry.forCluster(
      onOpenLibrary: _openLibrary,
      onToggleDemo: () => widget.state.updateGlobalSettings(
        widget.state.globalSettings.copyWith(
          demoMode: !widget.state.globalSettings.demoMode,
        ),
      ),
    );
    widget.state.addListener(_syncAppState);
    _sub = _sim.kph.listen((v) {
      _controller.speedKph = v;
    });
  }

  @override
  void dispose() {
    widget.state.removeListener(_syncAppState);
    _sub?.cancel();
    _sim.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _syncAppState() {
    _controller.design = widget.state.activeDesign;
    if (mounted) setState(() {});
  }

  void _openLibrary() => Navigator.of(
    context,
  ).pushNamed<void>('/library', arguments: LibrarySection.templates);

  void _openSettings() => Navigator.of(
    context,
  ).pushNamed<void>('/library', arguments: LibrarySection.settings);

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    _controller.reduceMotion = reduceMotion;

    final windowPadding = MediaQuery.paddingOf(context);
    final windowSize = MediaQuery.sizeOf(context);
    final currentOrientation = windowSize.width >= windowSize.height
        ? DesignOrientation.landscape
        : DesignOrientation.portrait;
    if (widget.state.activeDesign.supports(currentOrientation)) {
      _controller.orientation = currentOrientation;
    }

    return ColoredBox(
      color: const Color(0xFF000000),
      child: Stack(
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
                  renderAssets: widget.renderAssets,
                  controller: _controller,
                  safeInsets: windowPadding,
                ),
              );
            },
          ),
          DesignActionOverlay(
            design: widget.state.activeDesign,
            orientation: _controller.orientation,
            controller: _controller,
            registry: _actions,
            safeInsets: windowPadding,
          ),
          // Content insets to the safe area; the background does not.
          Padding(
            padding: windowPadding,
            child: Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: PrismButton(
                  // Auto-hide after a few seconds is still to come.
                  label: 'SET',
                  palette: VfdPalette.of(_controller.phosphor),
                  role: PrismRole.compact,
                  span: PrismSpan.one,
                  style: widget.state.activeDesign.renderSettings.prismStyle,
                  soundEnabled: widget.state.globalSettings.soundEnabled,
                  hapticsEnabled: widget.state.globalSettings.hapticsEnabled,
                  onPressed: _openSettings,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
