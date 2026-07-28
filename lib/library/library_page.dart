import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../editor/editor_page.dart';
import '../model/dashboard.dart';
import '../model/design_preset.dart';
import '../vfd/prism_widgets.dart';
import '../vfd/vfd_widgets.dart';

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key, required this.state, this.program});

  final AnodeState state;
  final ui.FragmentProgram? program;

  @override
  Widget build(BuildContext context) {
    final palette = VfdPalette.of(
      state.activeDesign.renderSettings.opticalProfile.phosphor,
    );
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: palette.unlit,
          title: VfdLegend('Library', palette: palette, lit: true, size: 16),
          bottom: TabBar(
            labelColor: palette.lit,
            unselectedLabelColor: palette.unlit,
            indicatorColor: palette.lit,
            dividerColor: palette.unlit.withValues(alpha: 0.25),
            tabs: const <Tab>[
              Tab(text: 'DESIGNS'),
              Tab(text: 'SETTINGS'),
            ],
          ),
        ),
        body: SafeArea(
          top: false,
          child: ListenableBuilder(
            listenable: state,
            builder: (context, _) => TabBarView(
              children: <Widget>[
                _DesignsTab(state: state, palette: palette, program: program),
                _SettingsTab(state: state, palette: palette),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesignsTab extends StatelessWidget {
  const _DesignsTab({
    required this.state,
    required this.palette,
    required this.program,
  });

  final AnodeState state;
  final VfdPalette palette;
  final ui.FragmentProgram? program;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: <Widget>[
      VfdLegend('Development scaffolds', palette: palette),
      const SizedBox(height: 8),
      for (final preset in state.presets) _presetCard(context, preset),
      const SizedBox(height: 24),
      VfdLegend('Your dashboards', palette: palette),
      const SizedBox(height: 8),
      if (state.dashboards.isEmpty)
        VfdLegend('No user dashboards', palette: palette),
      for (final dashboard in state.dashboards)
        _dashboardCard(context, dashboard),
    ],
  );

  Widget _presetCard(BuildContext context, DesignPreset preset) => _DesignCard(
    name: preset.name,
    detail: 'Immutable development scaffold • v${preset.version}',
    active: state.isActive(DesignKind.preset, preset.id),
    palette: palette,
    onActivate: () => state.activatePreset(preset),
    onEdit: () => _editPreset(context, preset),
  );

  Widget _dashboardCard(BuildContext context, Dashboard dashboard) =>
      _DesignCard(
        name: dashboard.name,
        detail: _dashboardDetail(dashboard),
        active: state.isActive(DesignKind.dashboard, dashboard.id),
        palette: palette,
        onActivate: () => state.activateDashboard(dashboard),
        onEdit: () => _openEditor(context, dashboard),
      );

  String _dashboardDetail(Dashboard dashboard) {
    final source = dashboard.sourcePresetId;
    if (source == null) return 'User dashboard';
    return 'User dashboard • forked from $source v'
        '${dashboard.sourcePresetVersion}';
  }

  void _editPreset(BuildContext context, DesignPreset preset) {
    final dashboard = state.forkPreset(preset);
    _openEditor(
      context,
      dashboard,
      forkedFrom: '${preset.name} v${preset.version}',
    );
  }

  void _openEditor(
    BuildContext context,
    Dashboard dashboard, {
    String? forkedFrom,
  }) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => EditorPage(
          dashboard: dashboard,
          forkedFrom: forkedFrom,
          program: program,
          soundEnabled: state.globalSettings.soundEnabled,
          hapticsEnabled: state.globalSettings.hapticsEnabled,
          onChanged: state.updateDashboard,
        ),
      ),
    );
  }
}

class _DesignCard extends StatelessWidget {
  const _DesignCard({
    required this.name,
    required this.detail,
    required this.active,
    required this.palette,
    required this.onActivate,
    required this.onEdit,
  });

  final String name;
  final String detail;
  final bool active;
  final VfdPalette palette;
  final VoidCallback onActivate;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final color = palette.state(active);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onActivate,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.55)),
          ),
          child: Row(
            children: <Widget>[
              Expanded(child: _description()),
              const SizedBox(width: 12),
              PrismButton(
                label: 'Edit',
                palette: palette,
                role: PrismRole.compact,
                onPressed: onEdit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _description() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      VfdLegend(name, palette: palette, lit: active, size: 14),
      const SizedBox(height: 6),
      VfdLegend(detail, palette: palette, size: 10),
      if (active) ...<Widget>[
        const SizedBox(height: 6),
        VfdLegend('Active', palette: palette, lit: true),
      ],
    ],
  );
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({required this.state, required this.palette});

  final AnodeState state;
  final VfdPalette palette;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: <Widget>[
      VfdLegend('Device feedback', palette: palette, size: 14),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          PrismButton(
            label: 'Sound',
            palette: palette,
            lit: state.globalSettings.soundEnabled,
            onPressed: () => state.updateGlobalSettings(
              state.globalSettings.copyWith(
                soundEnabled: !state.globalSettings.soundEnabled,
              ),
            ),
          ),
          PrismButton(
            label: 'Haptics',
            palette: palette,
            lit: state.globalSettings.hapticsEnabled,
            onPressed: () => state.updateGlobalSettings(
              state.globalSettings.copyWith(
                hapticsEnabled: !state.globalSettings.hapticsEnabled,
              ),
            ),
          ),
        ],
      ),
    ],
  );
}
