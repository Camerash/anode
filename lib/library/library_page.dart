import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../editor/editor_page.dart';
import '../mechanical/hard_cut_route.dart';
import '../mechanical/mechanical_pager.dart';
import '../mechanical/prism_selector_bank.dart';
import '../mechanical/vfd_editable_field.dart';
import '../model/dashboard.dart';
import '../model/design.dart';
import '../model/design_preset.dart';
import '../model/optical_profile.dart';
import '../platform/physical_interface_orientation.dart';
import '../vfd/prism_widgets.dart';
import '../vfd/vfd_render_assets.dart';
import '../vfd/vfd_widgets.dart';

enum LibrarySection { templates, designs, settings }

class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    required this.state,
    this.renderAssets,
    this.initialSection = LibrarySection.templates,
  });

  final AnodeState state;
  final VfdRenderAssets? renderAssets;
  final LibrarySection initialSection;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  late LibrarySection _section = widget.initialSection;

  VfdPalette get _palette => VfdPalette.of(
    widget.state.activeDesign.renderSettings.opticalProfile.phosphor,
  );

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFF000000),
    child: ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final safeInsets = MediaQuery.viewPaddingOf(context);
        return Column(
          children: <Widget>[
            SizedBox(
              height: safeInsets.top + 48,
              child: _topRail(context, safeInsets),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                safeInsets.left + 8,
                8,
                safeInsets.right + 8,
                8,
              ),
              child: KeyedSubtree(
                key: const ValueKey('library-section-selector'),
                child: PrismSelectorBank<LibrarySection>(
                  choices: <PrismSelectorChoice<LibrarySection>>[
                    for (final section in LibrarySection.values)
                      PrismSelectorChoice<LibrarySection>(
                        value: section,
                        label: section.name,
                        lit: section == _section,
                      ),
                  ],
                  selected: _section,
                  palette: _palette,
                  prismStyle:
                      widget.state.activeDesign.renderSettings.prismStyle,
                  rows: 1,
                  columns: 3,
                  role: PrismRole.compact,
                  soundEnabled: widget.state.globalSettings.soundEnabled,
                  hapticsEnabled: widget.state.globalSettings.hapticsEnabled,
                  semanticLabel: 'Library section',
                  onSelected: (value) => setState(() => _section = value),
                ),
              ),
            ),
            Expanded(
              child: ColoredBox(
                key: const ValueKey('library-content-environment'),
                color: const Color(0xFF000000),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    safeInsets.left,
                    0,
                    safeInsets.right,
                    safeInsets.bottom,
                  ),
                  child: KeyedSubtree(
                    key: const ValueKey('library-safe-content'),
                    child: _sectionBody(),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _sectionBody() => switch (_section) {
    LibrarySection.templates => _DesignBank(
      designs: widget.state.presets,
      emptyLabel: 'No templates',
      state: widget.state,
      palette: _palette,
      onActivate: (design) =>
          widget.state.activatePreset(design as DesignPreset),
      onClone: _requestClone,
    ),
    LibrarySection.designs => _DesignBank(
      designs: widget.state.dashboards,
      emptyLabel: 'No user designs · clone a template',
      state: widget.state,
      palette: _palette,
      onActivate: (design) =>
          widget.state.activateDashboard(design as Dashboard),
      onClone: _requestClone,
      onEdit: (design) => _openEditor(design as Dashboard),
    ),
    LibrarySection.settings => _SettingsBank(
      state: widget.state,
      palette: _palette,
    ),
  };

  Widget _topRail(BuildContext context, EdgeInsets safeInsets) => PrismPanel(
    key: const ValueKey('library-header-surface'),
    palette: _palette,
    padding: EdgeInsets.fromLTRB(
      safeInsets.left + 4,
      safeInsets.top + 2,
      safeInsets.right + 4,
      2,
    ),
    child: Row(
      children: <Widget>[
        PrismButton(
          key: const ValueKey('library-back'),
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

  Future<void> _requestClone(Design source) async {
    final name = await Navigator.of(context).push<String>(
      hardCutRoute<String>(
        (_) => _ClonePromptPage(
          sourceName: source.name,
          palette: _palette,
          prismStyle: widget.state.activeDesign.renderSettings.prismStyle,
          soundEnabled: widget.state.globalSettings.soundEnabled,
          hapticsEnabled: widget.state.globalSettings.hapticsEnabled,
        ),
      ),
    );
    if (!mounted || name == null) return;
    final trimmed = name.trim();
    final dashboard = switch (source) {
      DesignPreset preset => widget.state.forkPreset(
        preset,
        name: trimmed.isEmpty ? '${preset.name} copy' : trimmed,
      ),
      Dashboard design => widget.state.cloneDashboard(
        design,
        name: trimmed.isEmpty ? '${design.name} copy' : trimmed,
      ),
      _ => throw StateError('Unsupported design source ${source.runtimeType}'),
    };
    if (!mounted) return;
    _openEditor(dashboard);
  }

  void _openEditor(Dashboard dashboard) {
    Navigator.of(context).push<void>(
      hardCutRoute<void>(
        (_) => PhysicalInterfaceOrientationReader(
          builder: (context, interfaceOrientation) => EditorPage(
            dashboard: dashboard,
            interfaceOrientation: interfaceOrientation,
            renderAssets: widget.renderAssets,
            soundEnabled: widget.state.globalSettings.soundEnabled,
            hapticsEnabled: widget.state.globalSettings.hapticsEnabled,
            dockPreferences: widget.state.globalSettings.editorDock,
            onDockPreferencesChanged: (preferences) =>
                widget.state.updateGlobalSettings(
                  widget.state.globalSettings.copyWith(editorDock: preferences),
                ),
            onChanged: widget.state.updateDashboard,
          ),
        ),
      ),
    );
  }
}

class _DesignBank extends StatelessWidget {
  const _DesignBank({
    required this.designs,
    required this.emptyLabel,
    required this.state,
    required this.palette,
    required this.onActivate,
    required this.onClone,
    this.onEdit,
  });

  final List<Design> designs;
  final String emptyLabel;
  final AnodeState state;
  final VfdPalette palette;
  final ValueChanged<Design> onActivate;
  final ValueChanged<Design> onClone;
  final ValueChanged<Design>? onEdit;

  @override
  Widget build(BuildContext context) {
    if (designs.isEmpty) {
      return Center(child: VfdLegend(emptyLabel, palette: palette, size: 12));
    }
    return Padding(
      padding: const EdgeInsets.all(10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 8.0;
          const cardHeight = 142.0;
          final columns = constraints.maxWidth >= 720 ? 2 : 1;
          final rows = math.max(
            1,
            ((constraints.maxHeight + gap) / (cardHeight + gap)).floor(),
          );
          final pages = paginateCompleteRows(
            designs,
            columns: columns,
            rows: rows,
          );
          return MechanicalPager(
            pages: <Widget>[
              for (final page in pages)
                _DesignPage(
                  designs: page,
                  columns: columns,
                  cardHeight: cardHeight,
                  gap: gap,
                  state: state,
                  palette: palette,
                  onActivate: onActivate,
                  onClone: onClone,
                  onEdit: onEdit,
                ),
            ],
            palette: palette,
            prismStyle: state.activeDesign.renderSettings.prismStyle,
            soundEnabled: state.globalSettings.soundEnabled,
            hapticsEnabled: state.globalSettings.hapticsEnabled,
            semanticLabel: 'Design page',
          );
        },
      ),
    );
  }
}

class _DesignPage extends StatelessWidget {
  const _DesignPage({
    required this.designs,
    required this.columns,
    required this.cardHeight,
    required this.gap,
    required this.state,
    required this.palette,
    required this.onActivate,
    required this.onClone,
    required this.onEdit,
  });

  final List<Design> designs;
  final int columns;
  final double cardHeight;
  final double gap;
  final AnodeState state;
  final VfdPalette palette;
  final ValueChanged<Design> onActivate;
  final ValueChanged<Design> onClone;
  final ValueChanged<Design>? onEdit;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final cardWidth = (constraints.maxWidth - (columns - 1) * gap) / columns;
      return Align(
        alignment: Alignment.topCenter,
        child: Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (final design in designs)
              SizedBox(
                width: cardWidth,
                height: cardHeight,
                child: _DesignCard(
                  design: design,
                  active: state.isActive(
                    design is DesignPreset
                        ? DesignKind.preset
                        : DesignKind.dashboard,
                    design.id,
                  ),
                  palette: palette,
                  prismStyle: state.activeDesign.renderSettings.prismStyle,
                  soundEnabled: state.globalSettings.soundEnabled,
                  hapticsEnabled: state.globalSettings.hapticsEnabled,
                  onActivate: () => onActivate(design),
                  onClone: () => onClone(design),
                  onEdit: onEdit == null ? null : () => onEdit!(design),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _DesignCard extends StatelessWidget {
  const _DesignCard({
    required this.design,
    required this.active,
    required this.palette,
    required this.prismStyle,
    required this.soundEnabled,
    required this.hapticsEnabled,
    required this.onActivate,
    required this.onClone,
    this.onEdit,
  });

  final Design design;
  final bool active;
  final VfdPalette palette;
  final PrismStyle prismStyle;
  final bool soundEnabled;
  final bool hapticsEnabled;
  final VoidCallback onActivate;
  final VoidCallback onClone;
  final VoidCallback? onEdit;

  String get _detail => switch (design) {
    DesignPreset preset => 'Immutable template · v${preset.version}',
    Dashboard dashboard when dashboard.sourcePresetId != null =>
      'User design · from ${dashboard.sourcePresetId}',
    _ => 'User design',
  };

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: active,
    label: '${design.name}. $_detail',
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
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              VfdLegend(design.name, palette: palette, lit: active, size: 16),
              const SizedBox(height: 6),
              VfdLegend(_detail, palette: palette, size: 10),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  _action('Clone', onClone),
                  if (onEdit != null) ...<Widget>[
                    const SizedBox(width: 6),
                    _action('Edit', onEdit!),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _action(String label, VoidCallback callback) => PrismButton(
    label: label,
    palette: palette,
    role: PrismRole.compact,
    style: prismStyle,
    soundEnabled: soundEnabled,
    hapticsEnabled: hapticsEnabled,
    onPressed: callback,
  );
}

class _ClonePromptPage extends StatefulWidget {
  const _ClonePromptPage({
    required this.sourceName,
    required this.palette,
    required this.prismStyle,
    required this.soundEnabled,
    required this.hapticsEnabled,
  });

  final String sourceName;
  final VfdPalette palette;
  final PrismStyle prismStyle;
  final bool soundEnabled;
  final bool hapticsEnabled;

  @override
  State<_ClonePromptPage> createState() => _ClonePromptPageState();
}

class _ClonePromptPageState extends State<_ClonePromptPage> {
  late String _name = '${widget.sourceName} copy';

  @override
  Widget build(BuildContext context) => ColoredBox(
    key: const ValueKey('clone-prompt-environment'),
    color: const Color(0xFF020403),
    child: Padding(
      padding: MediaQuery.viewPaddingOf(context) + const EdgeInsets.all(12),
      child: Center(
        child: KeyedSubtree(
          key: const ValueKey('clone-prompt-safe-content'),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: PrismPanel(
              palette: widget.palette,
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  VfdLegend(
                    'Clone ${widget.sourceName}?',
                    palette: widget.palette,
                    lit: true,
                    size: 16,
                  ),
                  const SizedBox(height: 14),
                  VfdEditableField(
                    label: 'New design name',
                    value: _name,
                    palette: widget.palette,
                    onChanged: (value) => _name = value,
                    onSubmitted: (value) => Navigator.of(context).pop(value),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      _button('Cancel', () => Navigator.of(context).pop()),
                      const SizedBox(width: 8),
                      _button(
                        'Clone',
                        () => Navigator.of(context).pop(_name),
                        lit: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _button(String label, VoidCallback callback, {bool lit = false}) =>
      PrismButton(
        label: label,
        palette: widget.palette,
        lit: lit,
        role: PrismRole.standard,
        style: widget.prismStyle,
        soundEnabled: widget.soundEnabled,
        hapticsEnabled: widget.hapticsEnabled,
        onPressed: callback,
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
          if (kDebugMode) ...<Widget>[
            const SizedBox(height: 14),
            VfdLegend('Development', palette: palette, lit: true, size: 12),
            const SizedBox(height: 8),
            PrismButton(
              label: 'Debug bench',
              palette: palette,
              role: PrismRole.standard,
              span: PrismSpan.two,
              style: state.activeDesign.renderSettings.prismStyle,
              soundEnabled: state.globalSettings.soundEnabled,
              hapticsEnabled: state.globalSettings.hapticsEnabled,
              onPressed: () => Navigator.of(context).pushNamed<void>('/debug'),
            ),
          ],
        ],
      ),
    ),
  );
}
