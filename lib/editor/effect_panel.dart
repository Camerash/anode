import 'package:flutter/widgets.dart';

import '../mechanical/mechanical_lever.dart';
import '../mechanical/prism_selector_bank.dart';
import '../model/optical_profile.dart';
import '../vfd/prism_widgets.dart';
import '../vfd/vfd_types.dart';
import '../vfd/vfd_widgets.dart';
import 'effect_pictogram.dart';

const _phosphorChannel = '__phosphor__';

class EffectPanel extends StatefulWidget {
  const EffectPanel({
    super.key,
    required this.title,
    required this.dashboardProfile,
    required this.baseProfile,
    required this.scope,
    required this.prismStyle,
    required this.soundEnabled,
    required this.hapticsEnabled,
    this.overrides,
    this.onProfileChanged,
    this.onOverridesChanged,
    this.editable = true,
  });

  final String title;
  final OpticalProfile dashboardProfile;
  final OpticalProfile baseProfile;
  final OpticalOverrides? overrides;
  final EffectScope scope;
  final PrismStyle prismStyle;
  final bool soundEnabled;
  final bool hapticsEnabled;
  final bool editable;
  final ValueChanged<OpticalProfile>? onProfileChanged;
  final ValueChanged<OpticalOverrides>? onOverridesChanged;

  bool get local => overrides != null;

  @override
  State<EffectPanel> createState() => _EffectPanelState();
}

class _EffectPanelState extends State<EffectPanel> {
  String? _selectedChannel;

  OpticalProfile get _effective =>
      widget.baseProfile.apply(widget.overrides ?? OpticalOverrides());

  VfdPalette get _palette => VfdPalette.of(widget.dashboardProfile.phosphor);

  List<EffectSpec> get _effectSpecs {
    final known = EffectSpecs.forScope(widget.scope);
    return <EffectSpec>[
      ...known,
      for (final id in _unknownEffectIds) EffectSpecs.storageSpec(id),
    ];
  }

  List<String> get _unknownEffectIds {
    final ids = <String>{
      ...widget.dashboardProfile.effects.keys,
      ...widget.baseProfile.effects.keys,
      ...?widget.overrides?.effects.keys,
    };
    ids.removeWhere((id) => EffectSpecs.byId(id) != null);
    return ids.toList()..sort();
  }

  @override
  Widget build(BuildContext context) => PrismPanel(
    palette: _palette,
    padding: const EdgeInsets.all(10),
    child: _selectedChannel == null ? _overview() : _activeDetail(),
  );

  Widget _overview() => LayoutBuilder(
    builder: (context, constraints) {
      final rowHeight = PrismMetrics.height(PrismRole.standard);
      final rows = ((constraints.maxHeight - 29 + 6) / (rowHeight + 6))
          .floor()
          .clamp(1, 3);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          VfdLegend(widget.title, palette: _palette, lit: true, size: 12),
          const SizedBox(height: 8),
          PrismSelectorBank<String>(
            choices: <PrismSelectorChoice<String>>[
              PrismSelectorChoice<String>(
                value: _phosphorChannel,
                label: 'Phosphor',
                controlKey: const ValueKey('effect-phosphor'),
                lit: true,
                face: _icon(_phosphorChannel, lit: true),
              ),
              for (final spec in _effectSpecs)
                PrismSelectorChoice<String>(
                  value: spec.id,
                  label: spec.label,
                  controlKey: ValueKey('effect-${spec.id}'),
                  lit: _effective.effect(spec.id).enabled,
                  face: _icon(
                    spec.pictogramId,
                    lit: _effective.effect(spec.id).enabled,
                    enabled: EffectSpecs.byId(spec.id) != null,
                  ),
                ),
            ],
            selected: null,
            palette: _palette,
            prismStyle: widget.prismStyle,
            rows: rows,
            columns: constraints.maxWidth >= 360 ? 3 : 2,
            role: PrismRole.standard,
            soundEnabled: widget.soundEnabled,
            hapticsEnabled: widget.hapticsEnabled,
            semanticLabel: '${widget.title} channels',
            onSelected: (id) => setState(() => _selectedChannel = id),
          ),
        ],
      );
    },
  );

  Widget _activeDetail() {
    if (_selectedChannel == _phosphorChannel) return _phosphorDetail();
    final id = _selectedChannel;
    if (id == null) return const SizedBox.shrink();
    return _effectDetail(EffectSpecs.storageSpec(id));
  }

  Widget _channelHeader({
    required String id,
    required String title,
    required String description,
    required bool lit,
    required Widget? trailing,
  }) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: <Widget>[
      SizedBox(
        width: 74,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: PrismButton(
            key: ValueKey('active-effect-$id'),
            label: title,
            face: SizedBox(width: 34, height: 34, child: _icon(id, lit: lit)),
            palette: _palette,
            lit: lit,
            selected: true,
            role: PrismRole.standard,
            style: widget.prismStyle,
            soundEnabled: widget.soundEnabled,
            hapticsEnabled: widget.hapticsEnabled,
            onPressed: () => setState(() => _selectedChannel = null),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            VfdLegend(title, palette: _palette, lit: lit, size: 13),
            const SizedBox(height: 3),
            VfdLegend(description, palette: _palette, size: 9),
          ],
        ),
      ),
      if (trailing != null) ...<Widget>[const SizedBox(width: 6), trailing],
    ],
  );

  Widget _phosphorDetail() {
    final overridden = widget.overrides?.phosphorName != null;
    final editable = widget.editable && (!widget.local || overridden);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _channelHeader(
          id: _phosphorChannel,
          title: 'Phosphor',
          description: 'Colour of deposited phosphor emission.',
          lit: true,
          trailing: widget.local ? _phosphorOverrideButton(overridden) : null,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: PrismSelectorBank<String>(
            choices: <PrismSelectorChoice<String>>[
              for (final phosphor in Phosphor.all)
                PrismSelectorChoice<String>(
                  value: phosphor.name,
                  label: phosphor.name,
                  lit: _effective.phosphorName == phosphor.name,
                  enabled: editable,
                ),
            ],
            selected: _effective.phosphorName,
            palette: _palette,
            prismStyle: widget.prismStyle,
            rows: 1,
            role: PrismRole.compact,
            soundEnabled: widget.soundEnabled,
            hapticsEnabled: widget.hapticsEnabled,
            semanticLabel: 'Phosphor colour',
            onSelected: _setPhosphor,
          ),
        ),
      ],
    );
  }

  Widget _phosphorOverrideButton(bool overridden) => PrismButton(
    key: const ValueKey('phosphor-override'),
    label: overridden ? 'Override' : 'Inherit',
    palette: _palette,
    lit: overridden,
    enabled: widget.editable,
    role: PrismRole.compact,
    span: PrismSpan.two,
    style: widget.prismStyle,
    soundEnabled: widget.soundEnabled,
    hapticsEnabled: widget.hapticsEnabled,
    onPressed: widget.editable
        ? () => _setOverrides(
            overridden
                ? widget.overrides!.withPhosphor(null)
                : widget.overrides!.withPhosphor(
                    widget.baseProfile.phosphorName,
                  ),
          )
        : null,
  );

  Widget _effectDetail(EffectSpec spec) {
    final known = EffectSpecs.byId(spec.id) != null;
    final overridden = widget.overrides?.overrides(spec.id) ?? false;
    final editable = known && widget.editable && (!widget.local || overridden);
    final setting = _effective.effect(spec.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _channelHeader(
          id: spec.pictogramId,
          title: spec.label,
          description: spec.description,
          lit: setting.enabled,
          trailing: widget.local && known
              ? _overrideButton(spec, overridden)
              : null,
        ),
        const SizedBox(height: 8),
        MechanicalLever(
          key: ValueKey('effect-lever-${spec.id}'),
          label: '${spec.label} strength',
          value: setting.strength,
          min: 0,
          max: spec.maxStrength,
          step: 0.01,
          precision: spec.precision,
          tickCount: 21,
          referenceValue: spec.defaultStrength,
          offAtMinimum: true,
          leading: _icon(
            spec.pictogramId,
            lit: setting.enabled,
            enabled: known,
          ),
          palette: _palette,
          prismStyle: widget.prismStyle,
          soundEnabled: widget.soundEnabled,
          hapticsEnabled: widget.hapticsEnabled,
          onChanged: editable
              ? (value) => _setEffect(spec, setting.withStrength(value, spec))
              : null,
        ),
      ],
    );
  }

  Widget _icon(String id, {required bool lit, bool enabled = true}) =>
      EffectPictogram(id: id, palette: _palette, lit: lit, enabled: enabled);

  Widget _overrideButton(EffectSpec spec, bool overridden) => PrismButton(
    key: ValueKey('effect-override-${spec.id}'),
    label: overridden ? 'Override' : 'Inherit',
    palette: _palette,
    lit: overridden,
    enabled: widget.editable,
    role: PrismRole.compact,
    span: PrismSpan.two,
    style: widget.prismStyle,
    soundEnabled: widget.soundEnabled,
    hapticsEnabled: widget.hapticsEnabled,
    onPressed: widget.editable ? () => _toggleOverride(spec, overridden) : null,
  );

  void _toggleOverride(EffectSpec spec, bool overridden) {
    _setOverrides(
      widget.overrides!.withEffect(
        spec.id,
        overridden ? null : widget.baseProfile.effect(spec.id),
      ),
    );
  }

  void _setPhosphor(String value) {
    if (widget.local) {
      _setOverrides(widget.overrides!.withPhosphor(value));
    } else {
      widget.onProfileChanged?.call(widget.baseProfile.withPhosphor(value));
    }
  }

  void _setEffect(EffectSpec spec, EffectSetting value) {
    if (widget.local) {
      _setOverrides(widget.overrides!.withEffect(spec.id, value));
    } else {
      widget.onProfileChanged?.call(
        widget.baseProfile.withEffect(spec.id, value),
      );
    }
  }

  void _setOverrides(OpticalOverrides value) =>
      widget.onOverridesChanged?.call(value);
}

class PrismStyleEditor extends StatefulWidget {
  const PrismStyleEditor({
    super.key,
    required this.profile,
    required this.style,
    required this.soundEnabled,
    required this.hapticsEnabled,
    required this.onChanged,
  });

  final OpticalProfile profile;
  final PrismStyle style;
  final bool soundEnabled;
  final bool hapticsEnabled;
  final ValueChanged<PrismStyle> onChanged;

  @override
  State<PrismStyleEditor> createState() => _PrismStyleEditorState();
}

class _PrismStyleEditorState extends State<PrismStyleEditor> {
  String? _selected;

  static const _channels = <_PrismChannel>[
    _PrismChannel('depth', 'Cap depth', 0.06, 0.18, 0.12),
    _PrismChannel('smoke', 'Smoke density', 0.60, 0.95, 0.78),
    _PrismChannel('inactive', 'Inactive legend', 0, 0.5, 0.18),
    _PrismChannel('active', 'Active backlight', 0.25, 2, 1),
  ];

  VfdPalette get _palette => VfdPalette.of(widget.profile.phosphor);

  @override
  Widget build(BuildContext context) => PrismPanel(
    palette: _palette,
    padding: const EdgeInsets.all(10),
    child: _selected == null ? _overview() : _detail(),
  );

  Widget _overview() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      VfdLegend('Prism', palette: _palette, lit: true, size: 12),
      const SizedBox(height: 8),
      PrismSelectorBank<String>(
        choices: <PrismSelectorChoice<String>>[
          for (final channel in _channels)
            PrismSelectorChoice<String>(
              value: channel.id,
              label: channel.label,
            ),
        ],
        selected: null,
        palette: _palette,
        prismStyle: widget.style,
        rows: 2,
        soundEnabled: widget.soundEnabled,
        hapticsEnabled: widget.hapticsEnabled,
        semanticLabel: 'Prism style channels',
        onSelected: (id) => setState(() => _selected = id),
      ),
    ],
  );

  Widget _detail() {
    final channel = _channels.where((item) => item.id == _selected).firstOrNull;
    if (channel == null) return const SizedBox.shrink();
    final value = _value(channel.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            PrismButton(
              key: ValueKey('active-prism-${channel.id}'),
              label: channel.label,
              palette: _palette,
              lit: true,
              selected: true,
              role: PrismRole.standard,
              span: PrismSpan.two,
              style: widget.style,
              soundEnabled: widget.soundEnabled,
              hapticsEnabled: widget.hapticsEnabled,
              onPressed: () => setState(() => _selected = null),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: VfdLegend(
                channel.label,
                palette: _palette,
                lit: true,
                size: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        MechanicalLever(
          key: ValueKey('prism-lever-${channel.id}'),
          label: channel.label,
          value: value,
          min: channel.min,
          max: channel.max,
          step: 0.01,
          tickCount: 11,
          referenceValue: channel.reference,
          palette: _palette,
          prismStyle: widget.style,
          soundEnabled: widget.soundEnabled,
          hapticsEnabled: widget.hapticsEnabled,
          onChanged: (next) => _setValue(channel.id, next),
        ),
      ],
    );
  }

  double _value(String id) => switch (id) {
    'depth' => widget.style.bevelDepth,
    'smoke' => widget.style.faceOpacity,
    'inactive' => widget.style.inactiveLuminosity,
    'active' => widget.style.activeLuminosity,
    _ => 0,
  };

  void _setValue(String id, double value) {
    widget.onChanged(switch (id) {
      'depth' => widget.style.copyWith(bevelDepth: value),
      'smoke' => widget.style.copyWith(faceOpacity: value),
      'inactive' => widget.style.copyWith(inactiveLuminosity: value),
      'active' => widget.style.copyWith(activeLuminosity: value),
      _ => widget.style,
    });
  }
}

class _PrismChannel {
  const _PrismChannel(this.id, this.label, this.min, this.max, this.reference);

  final String id;
  final String label;
  final double min;
  final double max;
  final double reference;
}
