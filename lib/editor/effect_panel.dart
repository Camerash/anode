import 'package:flutter/widgets.dart';

import '../mechanical/mechanical_flip_tray.dart';
import '../mechanical/prism_selector_bank.dart';
import '../model/optical_profile.dart';
import '../vfd/prism_widgets.dart';
import '../vfd/vfd_types.dart';
import '../vfd/vfd_widgets.dart';

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
    child: LayoutBuilder(
      builder: (context, constraints) {
        final rows = constraints.maxHeight >= 292 ? 2 : 1;
        final bankHeight =
            rows * PrismMetrics.height(PrismRole.standard) + (rows - 1) * 6;
        final trayHeight = (constraints.maxHeight - bankHeight - 31).clamp(
          0.0,
          150.0,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            VfdLegend(widget.title, palette: _palette, lit: true, size: 12),
            const SizedBox(height: 8),
            _channelBank(rows),
            const SizedBox(height: 8),
            SizedBox(height: trayHeight, child: _detailTray()),
          ],
        );
      },
    ),
  );

  Widget _channelBank(int rows) {
    final choices = <PrismSelectorChoice<String>>[
      PrismSelectorChoice<String>(
        value: _phosphorChannel,
        label: 'PHOSPHOR',
        controlKey: const ValueKey('effect-phosphor'),
        lit: true,
      ),
      for (final spec in _effectSpecs)
        PrismSelectorChoice<String>(
          value: spec.id,
          label: spec.controlLabel,
          controlKey: ValueKey('effect-${spec.id}'),
          lit: _effective.effect(spec.id).enabled,
          enabled: EffectSpecs.byId(spec.id) != null,
        ),
    ];
    return PrismSelectorBank<String>(
      choices: choices,
      selected: _selectedChannel,
      palette: _palette,
      prismStyle: widget.prismStyle,
      rows: rows,
      role: PrismRole.standard,
      soundEnabled: widget.soundEnabled,
      hapticsEnabled: widget.hapticsEnabled,
      semanticLabel: '${widget.title} channels',
      onSelected: _selectChannel,
    );
  }

  Widget _detailTray() => LayoutBuilder(
    builder: (context, constraints) => MechanicalFlipTray(
      open: _selectedChannel != null,
      height: constraints.maxHeight,
      palette: _palette,
      soundEnabled: widget.soundEnabled,
      hapticsEnabled: widget.hapticsEnabled,
      child: Padding(
        padding: const EdgeInsets.all(9),
        child: _selectedChannel == _phosphorChannel
            ? _phosphorDetail()
            : _effectDetail(_selectedEffect),
      ),
    ),
  );

  EffectSpec? get _selectedEffect {
    final id = _selectedChannel;
    if (id == null || id == _phosphorChannel) return null;
    return EffectSpecs.storageSpec(id);
  }

  Widget _phosphorDetail() {
    final overridden = widget.overrides?.phosphorName != null;
    final editable = widget.editable && (!widget.local || overridden);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: VfdLegend(
                'Phosphor',
                palette: _palette,
                lit: true,
                size: 13,
              ),
            ),
            if (widget.local) _phosphorOverrideButton(overridden),
          ],
        ),
        const SizedBox(height: 5),
        VfdLegend(
          'Colour of deposited phosphor emission.',
          palette: _palette,
          size: 9,
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

  Widget _effectDetail(EffectSpec? spec) {
    if (spec == null) return const SizedBox.shrink();
    final known = EffectSpecs.byId(spec.id) != null;
    final overridden = widget.overrides?.overrides(spec.id) ?? false;
    final editable = known && widget.editable && (!widget.local || overridden);
    final setting = _effective.effect(spec.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: VfdLegend(
                spec.label,
                palette: _palette,
                lit: setting.enabled,
                size: 13,
              ),
            ),
            if (widget.local && known) ...<Widget>[
              _overrideButton(spec, overridden),
              const SizedBox(width: 6),
            ],
            _powerButton(spec, setting, editable),
          ],
        ),
        const SizedBox(height: 4),
        VfdLegend(spec.description, palette: _palette, size: 9),
        const Spacer(),
        Opacity(
          opacity: editable ? 1 : 0.42,
          child: Row(
            children: <Widget>[
              Expanded(
                child: VfdCellBar(
                  key: ValueKey('effect-bar-${spec.id}'),
                  value: setting.strength,
                  min: 0,
                  max: spec.maxStrength,
                  palette: _palette,
                  cells: 32,
                  height: 20,
                  step: spec.step,
                  precision: spec.precision,
                  semanticLabel: '${spec.label} strength',
                  onChanged: editable
                      ? (value) =>
                            _setEffect(spec, setting.withStrength(value, spec))
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 42,
                child: VfdLegend(
                  setting.strength.toStringAsFixed(spec.precision),
                  palette: _palette,
                  lit: setting.enabled,
                  size: 11,
                ),
              ),
              _stepButton('-', spec, setting, editable, -spec.step),
              const SizedBox(width: 5),
              _stepButton('+', spec, setting, editable, spec.step),
            ],
          ),
        ),
      ],
    );
  }

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

  Widget _powerButton(EffectSpec spec, EffectSetting setting, bool editable) =>
      PrismButton(
        key: ValueKey('effect-power-${spec.id}'),
        label: setting.enabled ? 'On' : 'Off',
        palette: _palette,
        lit: setting.enabled,
        enabled: editable,
        role: PrismRole.compact,
        style: widget.prismStyle,
        soundEnabled: widget.soundEnabled,
        hapticsEnabled: widget.hapticsEnabled,
        onPressed: editable
            ? () => _setEffect(spec, setting.toggled(spec))
            : null,
      );

  Widget _stepButton(
    String label,
    EffectSpec spec,
    EffectSetting setting,
    bool editable,
    double delta,
  ) => PrismButton(
    label: label,
    palette: _palette,
    enabled: editable,
    role: PrismRole.compact,
    style: widget.prismStyle,
    soundEnabled: widget.soundEnabled,
    hapticsEnabled: widget.hapticsEnabled,
    onPressed: editable
        ? () => _setEffect(
            spec,
            setting.withStrength(setting.strength + delta, spec),
          )
        : null,
  );

  void _selectChannel(String id) {
    setState(() => _selectedChannel = _selectedChannel == id ? null : id);
  }

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
    _PrismChannel('depth', 'Cap depth', 0.06, 0.18),
    _PrismChannel('smoke', 'Smoke density', 0.60, 0.95),
    _PrismChannel('inactive', 'Inactive legend', 0, 0.5),
    _PrismChannel('active', 'Active backlight', 0.25, 2),
  ];

  VfdPalette get _palette => VfdPalette.of(widget.profile.phosphor);

  @override
  Widget build(BuildContext context) => PrismPanel(
    palette: _palette,
    padding: const EdgeInsets.all(10),
    child: Column(
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
                lit: _selected == channel.id,
              ),
          ],
          selected: _selected,
          palette: _palette,
          prismStyle: widget.style,
          rows: 2,
          soundEnabled: widget.soundEnabled,
          hapticsEnabled: widget.hapticsEnabled,
          semanticLabel: 'Prism style channels',
          onSelected: (id) =>
              setState(() => _selected = _selected == id ? null : id),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 140,
          child: MechanicalFlipTray(
            open: _selected != null,
            height: 140,
            palette: _palette,
            soundEnabled: widget.soundEnabled,
            hapticsEnabled: widget.hapticsEnabled,
            child: _styleDetail(),
          ),
        ),
      ],
    ),
  );

  Widget _styleDetail() {
    final channel = _channels.where((item) => item.id == _selected).firstOrNull;
    if (channel == null) return const SizedBox.shrink();
    final value = _value(channel.id);
    return Padding(
      padding: const EdgeInsets.all(9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          VfdLegend(channel.label, palette: _palette, lit: true, size: 13),
          const Spacer(),
          Row(
            children: <Widget>[
              Expanded(
                child: VfdCellBar(
                  value: value,
                  min: channel.min,
                  max: channel.max,
                  palette: _palette,
                  step: 0.01,
                  precision: 2,
                  semanticLabel: channel.label,
                  onChanged: (next) => _setValue(channel.id, next),
                ),
              ),
              const SizedBox(width: 8),
              VfdLegend(
                value.toStringAsFixed(2),
                palette: _palette,
                lit: true,
                size: 11,
              ),
              const SizedBox(width: 8),
              _styleStep('-', channel, value, -0.01),
              const SizedBox(width: 5),
              _styleStep('+', channel, value, 0.01),
            ],
          ),
        ],
      ),
    );
  }

  Widget _styleStep(
    String label,
    _PrismChannel channel,
    double value,
    double delta,
  ) => PrismButton(
    label: label,
    palette: _palette,
    role: PrismRole.compact,
    style: widget.style,
    soundEnabled: widget.soundEnabled,
    hapticsEnabled: widget.hapticsEnabled,
    onPressed: () =>
        _setValue(channel.id, (value + delta).clamp(channel.min, channel.max)),
  );

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
  const _PrismChannel(this.id, this.label, this.min, this.max);

  final String id;
  final String label;
  final double min;
  final double max;
}
