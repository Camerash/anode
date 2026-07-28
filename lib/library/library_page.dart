import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../editor/editor_page.dart';
import '../mechanical/hard_cut_route.dart';
import '../mechanical/mechanical_pager.dart';
import '../mechanical/prism_selector_bank.dart';
import '../model/dashboard.dart';
import '../model/design_preset.dart';
import '../model/optical_profile.dart';
import '../vfd/prism_widgets.dart';
import '../vfd/vfd_render_assets.dart';
import '../vfd/vfd_widgets.dart';

enum _LibrarySection { designs, settings }

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.state, this.renderAssets});

  final AnodeState state;
  final VfdRenderAssets? renderAssets;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  _LibrarySection _section = _LibrarySection.designs;

  VfdPalette get _palette => VfdPalette.of(
    widget.state.activeDesign.renderSettings.opticalProfile.phosphor,
  );

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFF000000),
    child: SafeArea(
      child: ListenableBuilder(
        listenable: widget.state,
        builder: (context, _) => Column(
          children: <Widget>[
            SizedBox(height: 48, child: _topRail(context)),
            Padding(
              padding: const EdgeInsets.all(8),
              child: PrismSelectorBank<_LibrarySection>(
                choices: <PrismSelectorChoice<_LibrarySection>>[
                  for (final section in _LibrarySection.values)
                    PrismSelectorChoice<_LibrarySection>(
                      value: section,
                      label: section.name,
                      lit: section == _section,
                    ),
                ],
                selected: _section,
                palette: _palette,
                prismStyle: widget.state.activeDesign.renderSettings.prismStyle,
                rows: 1,
                columns: 2,
                role: PrismRole.compact,
                soundEnabled: widget.state.globalSettings.soundEnabled,
                hapticsEnabled: widget.state.globalSettings.hapticsEnabled,
                semanticLabel: 'Library section',
                onSelected: (value) => setState(() => _section = value),
              ),
            ),
            Expanded(
              child: _section == _LibrarySection.designs
                  ? _DesignsBank(
                      state: widget.state,
                      palette: _palette,
                      renderAssets: widget.renderAssets,
                    )
                  : _SettingsBank(state: widget.state, palette: _palette),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _topRail(BuildContext context) => PrismPanel(
    palette: _palette,
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    child: Row(
      children: <Widget>[
        PrismButton(
          label: 'Back',
          palette: _palette,
          role: PrismRole.compact,
          style: widget.state.activeDesign.renderSettings.prismStyle,
          soundEnabled: widget.state.globalSettings.soundEnabled,
          hapticsEnabled: widget.state.globalSettings.hapticsEnabled,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: VfdLegend('Library', palette: _palette, lit: true, size: 15),
        ),
      ],
    ),
  );
}

class _DesignsBank extends StatelessWidget {
  const _DesignsBank({
    required this.state,
    required this.palette,
    required this.renderAssets,
  });

  final AnodeState state;
  final VfdPalette palette;
  final VfdRenderAssets? renderAssets;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      for (final preset in state.presets) _presetCard(context, preset),
      for (final dashboard in state.dashboards)
        _dashboardCard(context, dashboard),
    ];
    if (cards.isEmpty) {
      return Center(child: VfdLegend('No designs', palette: palette, size: 12));
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: MechanicalPager(
        pages: cards,
        palette: palette,
        prismStyle: state.activeDesign.renderSettings.prismStyle,
        soundEnabled: state.globalSettings.soundEnabled,
        hapticsEnabled: state.globalSettings.hapticsEnabled,
        semanticLabel: 'Design',
      ),
    );
  }

  Widget _presetCard(BuildContext context, DesignPreset preset) => _DesignCard(
    name: preset.name,
    detail: 'Immutable development scaffold · v${preset.version}',
    active: state.isActive(DesignKind.preset, preset.id),
    palette: palette,
    prismStyle: state.activeDesign.renderSettings.prismStyle,
    soundEnabled: state.globalSettings.soundEnabled,
    hapticsEnabled: state.globalSettings.hapticsEnabled,
    onActivate: () => state.activatePreset(preset),
    onEdit: () => _editPreset(context, preset),
  );

  Widget _dashboardCard(BuildContext context, Dashboard dashboard) =>
      _DesignCard(
        name: dashboard.name,
        detail: _dashboardDetail(dashboard),
        active: state.isActive(DesignKind.dashboard, dashboard.id),
        palette: palette,
        prismStyle: state.activeDesign.renderSettings.prismStyle,
        soundEnabled: state.globalSettings.soundEnabled,
        hapticsEnabled: state.globalSettings.hapticsEnabled,
        onActivate: () => state.activateDashboard(dashboard),
        onEdit: () => _openEditor(context, dashboard),
      );

  String _dashboardDetail(Dashboard dashboard) {
    final source = dashboard.sourcePresetId;
    if (source == null) return 'User dashboard';
    return 'User dashboard · forked from $source v${dashboard.sourcePresetVersion}';
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
      hardCutRoute<void>(
        (_) => EditorPage(
          dashboard: dashboard,
          forkedFrom: forkedFrom,
          renderAssets: renderAssets,
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
    required this.prismStyle,
    required this.soundEnabled,
    required this.hapticsEnabled,
    required this.onActivate,
    required this.onEdit,
  });

  final String name;
  final String detail;
  final bool active;
  final VfdPalette palette;
  final PrismStyle prismStyle;
  final bool soundEnabled;
  final bool hapticsEnabled;
  final VoidCallback onActivate;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: active,
    label: '$name. $detail',
    onTap: onActivate,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onActivate,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF050807),
          border: Border.all(
            color: palette.state(active).withValues(alpha: active ? 0.9 : 0.4),
            width: active ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              VfdLegend(name, palette: palette, lit: active, size: 18),
              const SizedBox(height: 10),
              VfdLegend(detail, palette: palette, size: 11),
              if (active) ...<Widget>[
                const SizedBox(height: 9),
                VfdLegend('Active', palette: palette, lit: true, size: 11),
              ],
              const Spacer(),
              Align(
                alignment: Alignment.bottomRight,
                child: PrismButton(
                  label: 'Edit',
                  palette: palette,
                  role: PrismRole.standard,
                  span: PrismSpan.one,
                  style: prismStyle,
                  soundEnabled: soundEnabled,
                  hapticsEnabled: hapticsEnabled,
                  onPressed: onEdit,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SettingsBank extends StatelessWidget {
  const _SettingsBank({required this.state, required this.palette});

  final AnodeState state;
  final VfdPalette palette;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: PrismPanel(
      palette: palette,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          VfdLegend('Device feedback', palette: palette, lit: true, size: 14),
          const SizedBox(height: 14),
          PrismSelectorBank<String>(
            choices: <PrismSelectorChoice<String>>[
              PrismSelectorChoice<String>(
                value: 'sound',
                label: 'Sound',
                lit: state.globalSettings.soundEnabled,
              ),
              PrismSelectorChoice<String>(
                value: 'haptics',
                label: 'Haptics',
                lit: state.globalSettings.hapticsEnabled,
              ),
            ],
            selected: null,
            palette: palette,
            prismStyle: state.activeDesign.renderSettings.prismStyle,
            rows: 1,
            columns: 2,
            soundEnabled: state.globalSettings.soundEnabled,
            hapticsEnabled: state.globalSettings.hapticsEnabled,
            semanticLabel: 'Device feedback',
            onSelected: (id) {
              if (id == 'sound') {
                state.updateGlobalSettings(
                  state.globalSettings.copyWith(
                    soundEnabled: !state.globalSettings.soundEnabled,
                  ),
                );
              } else {
                state.updateGlobalSettings(
                  state.globalSettings.copyWith(
                    hapticsEnabled: !state.globalSettings.hapticsEnabled,
                  ),
                );
              }
            },
          ),
        ],
      ),
    ),
  );
}
