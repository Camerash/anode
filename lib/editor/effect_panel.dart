import 'package:flutter/material.dart';

import '../model/optical_profile.dart';
import '../vfd/prism_widgets.dart';
import '../vfd/vfd_types.dart';
import '../vfd/vfd_widgets.dart';

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

  /// Drives panel chrome even while local values use another phosphor colour.
  final OpticalProfile dashboardProfile;

  /// Inherited profile before [overrides] are applied.
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

class PrismStyleEditor extends StatelessWidget {
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

  VfdPalette get _palette => VfdPalette.of(profile.phosphor);

  @override
  Widget build(BuildContext context) => PrismPanel(
    palette: _palette,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        VfdLegend('Prism style', palette: _palette, lit: true, size: 13),
        const SizedBox(height: 4),
        Text(
          'Dashboard-wide smoked acrylic control geometry and luminosity.',
          style: TextStyle(color: _palette.unlit),
        ),
        const SizedBox(height: 14),
        _control(
          label: 'Bevel depth',
          value: style.bevelDepth,
          max: 0.3,
          onChanged: (value) => onChanged(style.copyWith(bevelDepth: value)),
        ),
        _control(
          label: 'Face opacity',
          value: style.faceOpacity,
          max: 1,
          onChanged: (value) => onChanged(style.copyWith(faceOpacity: value)),
        ),
        _control(
          label: 'Inactive luminosity',
          value: style.inactiveLuminosity,
          max: 1,
          onChanged: (value) =>
              onChanged(style.copyWith(inactiveLuminosity: value)),
        ),
        _control(
          label: 'Active luminosity',
          value: style.activeLuminosity,
          max: 2,
          onChanged: (value) =>
              onChanged(style.copyWith(activeLuminosity: value)),
        ),
      ],
    ),
  );

  Widget _control({
    required String label,
    required double value,
    required double max,
    required ValueChanged<double> onChanged,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: VfdLegend(label, palette: _palette, size: 10)),
            VfdLegend(
              value.toStringAsFixed(2),
              palette: _palette,
              lit: true,
              size: 10,
            ),
            const SizedBox(width: 8),
            PrismButton(
              label: '−',
              palette: _palette,
              role: PrismRole.compact,
              style: style,
              soundEnabled: soundEnabled,
              hapticsEnabled: hapticsEnabled,
              onPressed: () => onChanged((value - 0.01).clamp(0, max)),
            ),
            const SizedBox(width: 6),
            PrismButton(
              label: '+',
              palette: _palette,
              role: PrismRole.compact,
              style: style,
              soundEnabled: soundEnabled,
              hapticsEnabled: hapticsEnabled,
              onPressed: () => onChanged((value + 0.01).clamp(0, max)),
            ),
          ],
        ),
        const SizedBox(height: 7),
        VfdCellBar(
          value: value,
          min: 0,
          max: max,
          cells: 24,
          palette: _palette,
          onChanged: onChanged,
        ),
      ],
    ),
  );
}

class _EffectPanelState extends State<EffectPanel> {
  String? _selectedEffectId;

  List<EffectSpec> get _specs => EffectSpecs.forScope(widget.scope);

  EffectSpec get _selectedSpec {
    final selected = _selectedEffectId;
    if (selected != null) {
      final found = EffectSpecs.byId(selected);
      if (found != null && found.supports(widget.scope)) return found;
    }
    return _specs.first;
  }

  OpticalProfile get _effective =>
      widget.baseProfile.apply(widget.overrides ?? OpticalOverrides());

  VfdPalette get _palette => VfdPalette.of(widget.dashboardProfile.phosphor);

  @override
  Widget build(BuildContext context) => PrismPanel(
    palette: _palette,
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          VfdLegend(widget.title, palette: _palette, lit: true, size: 13),
          const SizedBox(height: 12),
          _colorControls(),
          const SizedBox(height: 14),
          _effectGrid(),
          const SizedBox(height: 16),
          _effectDetail(_selectedSpec),
          if (_unknownEffectIds.isNotEmpty) ...<Widget>[
            const SizedBox(height: 18),
            VfdLegend('Unavailable effects', palette: _palette, size: 10),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final id in _unknownEffectIds)
                  PrismButton(
                    label: id,
                    value: _effective.effect(id).strength.toStringAsFixed(2),
                    palette: _palette,
                    lit: _effective.effect(id).enabled,
                    enabled: false,
                    role: PrismRole.standard,
                    style: widget.prismStyle,
                    onPressed: null,
                  ),
              ],
            ),
          ],
        ],
      ),
    ),
  );

  List<String> get _unknownEffectIds {
    final ids = <String>{
      ...widget.dashboardProfile.effects.keys,
      ...widget.baseProfile.effects.keys,
      ...?widget.overrides?.effects.keys,
    };
    ids.removeWhere((id) => EffectSpecs.byId(id) != null);
    return ids.toList()..sort();
  }

  Widget _colorControls() {
    final local = widget.local;
    final overrides = widget.overrides;
    final overridden = overrides?.phosphorName != null;
    final enabled = widget.editable && (!local || overridden);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: VfdLegend('Phosphor', palette: _palette, size: 10)),
            if (local)
              PrismButton(
                key: const ValueKey('phosphor-override'),
                label: overridden ? 'Override' : 'Inherit',
                palette: _palette,
                lit: overridden,
                enabled: widget.editable,
                role: PrismRole.compact,
                style: widget.prismStyle,
                soundEnabled: widget.soundEnabled,
                hapticsEnabled: widget.hapticsEnabled,
                onPressed: widget.editable
                    ? () => _setOverrides(
                        overridden
                            ? overrides!.withPhosphor(null)
                            : overrides!.withPhosphor(
                                widget.baseProfile.phosphorName,
                              ),
                      )
                    : null,
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: <Widget>[
            for (final phosphor in Phosphor.all)
              PrismButton(
                label: phosphor.name,
                palette: _palette,
                lit: _effective.phosphorName == phosphor.name,
                selected: _effective.phosphorName == phosphor.name,
                enabled: enabled,
                role: PrismRole.compact,
                style: widget.prismStyle,
                soundEnabled: widget.soundEnabled,
                hapticsEnabled: widget.hapticsEnabled,
                onPressed: enabled ? () => _setPhosphor(phosphor.name) : null,
              ),
          ],
        ),
      ],
    );
  }

  Widget _effectGrid() => LayoutBuilder(
    builder: (context, constraints) {
      const columns = 3;
      const gap = 8.0;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: <Widget>[
          for (final spec in _specs)
            SizedBox(
              width: width,
              child: PrismButton(
                key: ValueKey('effect-${spec.id}'),
                label: spec.label,
                value: _effective
                    .effect(spec.id)
                    .strength
                    .toStringAsFixed(spec.precision),
                palette: _palette,
                lit: _effective.effect(spec.id).enabled,
                selected: _selectedSpec.id == spec.id,
                role: PrismRole.standard,
                style: widget.prismStyle,
                soundEnabled: widget.soundEnabled,
                hapticsEnabled: widget.hapticsEnabled,
                onPressed: () => setState(() => _selectedEffectId = spec.id),
              ),
            ),
        ],
      );
    },
  );

  Widget _effectDetail(EffectSpec spec) {
    final overrides = widget.overrides;
    final overridden = overrides?.overrides(spec.id) ?? false;
    final editable = widget.editable && (!widget.local || overridden);
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
                size: 14,
              ),
            ),
            if (widget.local) ...<Widget>[
              PrismButton(
                key: ValueKey('effect-override-${spec.id}'),
                label: overridden ? 'Override' : 'Inherit',
                palette: _palette,
                lit: overridden,
                enabled: widget.editable,
                role: PrismRole.compact,
                style: widget.prismStyle,
                soundEnabled: widget.soundEnabled,
                hapticsEnabled: widget.hapticsEnabled,
                onPressed: widget.editable
                    ? () => _toggleOverride(spec, overridden)
                    : null,
              ),
              const SizedBox(width: 8),
            ],
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
            ),
          ],
        ),
        const SizedBox(height: 8),
        VfdLegend(spec.description, palette: _palette, size: 9),
        const SizedBox(height: 12),
        IgnorePointer(
          ignoring: !editable,
          child: Opacity(
            opacity: editable ? 1 : 0.42,
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: <Widget>[
                  VfdCellBar(
                    value: setting.strength,
                    min: 0,
                    max: spec.maxStrength,
                    palette: _palette,
                    cells: 40,
                    height: 20,
                    onChanged: (value) =>
                        _setEffect(spec, setting.withStrength(value, spec)),
                  ),
                  Positioned(
                    left: constraints.maxWidth / spec.maxStrength - 0.5,
                    top: -2,
                    bottom: -2,
                    child: Container(
                      width: 1,
                      color: _palette.unlit.withValues(alpha: 0.72),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 9),
        Row(
          children: <Widget>[
            Expanded(
              child: VfdLegend(
                setting.strength.toStringAsFixed(spec.precision),
                palette: _palette,
                lit: setting.enabled,
                size: 13,
              ),
            ),
            PrismButton(
              label: '−',
              palette: _palette,
              enabled: editable,
              role: PrismRole.compact,
              style: widget.prismStyle,
              soundEnabled: widget.soundEnabled,
              hapticsEnabled: widget.hapticsEnabled,
              onPressed: editable
                  ? () => _setEffect(
                      spec,
                      setting.withStrength(setting.strength - spec.step, spec),
                    )
                  : null,
            ),
            const SizedBox(width: 7),
            PrismButton(
              label: '+',
              palette: _palette,
              enabled: editable,
              role: PrismRole.compact,
              style: widget.prismStyle,
              soundEnabled: widget.soundEnabled,
              hapticsEnabled: widget.hapticsEnabled,
              onPressed: editable
                  ? () => _setEffect(
                      spec,
                      setting.withStrength(setting.strength + spec.step, spec),
                    )
                  : null,
            ),
          ],
        ),
      ],
    );
  }

  void _toggleOverride(EffectSpec spec, bool overridden) {
    final overrides = widget.overrides!;
    _setOverrides(
      overrides.withEffect(
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
