import 'package:flutter/widgets.dart';

import '../mechanical/mechanical_channel_drum.dart';
import '../mechanical/mechanical_lever.dart';
import '../mechanical/prism_selector_bank.dart';
import '../model/optical_profile.dart';
import '../vfd/prism_widgets.dart';
import '../vfd/vfd_types.dart';
import '../vfd/vfd_widgets.dart';
import 'effect_pictogram.dart';

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
    this.contentSafeInsets = EdgeInsets.zero,
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
  final EdgeInsets contentSafeInsets;
  final bool editable;
  final ValueChanged<OpticalProfile>? onProfileChanged;
  final ValueChanged<OpticalOverrides>? onOverridesChanged;

  bool get local => overrides != null;

  @override
  State<EffectPanel> createState() => _EffectPanelState();
}

class _EffectPanelState extends State<EffectPanel> {
  static const _phosphorChannelId = '__phosphor__';
  static const _phosphorChannel = EffectSpec(
    id: _phosphorChannelId,
    label: 'Phosphor',
    description: 'Select the phosphor color for the VFD light.',
    pictogramId: _phosphorChannelId,
    scopes: <EffectScope>{
      EffectScope.dashboard,
      EffectScope.module,
      EffectScope.component,
    },
  );

  int _serviceIndex = 0;

  OpticalProfile get _effective =>
      widget.baseProfile.apply(widget.overrides ?? OpticalOverrides());

  VfdPalette get _palette => VfdPalette.of(widget.dashboardProfile.phosphor);

  List<EffectSpec> get _effectSpecs {
    final known = EffectSpecs.forScope(widget.scope);
    return <EffectSpec>[
      _phosphorChannel,
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
    padding: EdgeInsets.fromLTRB(4, 4, 4, 4 + widget.contentSafeInsets.bottom),
    child: _serviceFace(),
  );

  Widget _phosphorButton({
    required Key key,
    required String label,
    required String? value,
    required bool selected,
    required bool enabled,
  }) => _fitButton(
    key: key,
    label: label,
    lit: selected,
    selected: selected,
    enabled: enabled,
    onPressed: () => _setPhosphor(value),
  );

  Widget _serviceFace() {
    final specs = _effectSpecs;
    final index = _serviceIndex.clamp(0, specs.length - 1);
    final spec = specs[index];
    final isPhosphor = spec.id == _phosphorChannelId;
    final known = isPhosphor || EffectSpecs.byId(spec.id) != null;
    final editable =
        known && widget.editable && (!widget.local || _isOverridden(spec));
    final setting = _effective.effect(spec.id);
    return ColoredBox(
      color: const Color(0xFF050706),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 7),
        child: Column(
          children: <Widget>[
            MechanicalCarousel<EffectSpec>(
              items: specs,
              index: index,
              labelFor: (item) => item.label,
              itemBuilder: (context, item, selected, size) =>
                  _carouselItem(item, selected: selected, size: size),
              palette: _palette,
              prismStyle: widget.prismStyle,
              soundEnabled: widget.soundEnabled,
              hapticsEnabled: widget.hapticsEnabled,
              semanticLabel: 'Effect channel',
              previousKey: const ValueKey('service-effect-previous'),
              nextKey: const ValueKey('service-effect-next'),
              onChanged: (value) => setState(() => _serviceIndex = value),
            ),
            const SizedBox(height: 5),
            SizedBox(
              key: ValueKey('effect-description-${spec.id}'),
              height: 44,
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: VfdLegend(
                        spec.description,
                        palette: _palette,
                        lit: true,
                        size: 11,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (widget.local && known) ...<Widget>[
                    const SizedBox(width: 5),
                    _serviceButton(
                      key: ValueKey('effect-override-${spec.id}'),
                      label: 'Override',
                      lit: _isOverridden(spec),
                      enabled: widget.editable,
                      onPressed: () =>
                          _toggleOverride(spec, _isOverridden(spec)),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 5),
            Expanded(
              child: _controlDeck(
                spec: spec,
                setting: setting,
                isPhosphor: isPhosphor,
                editable: editable,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _carouselItem(
    EffectSpec spec, {
    required bool selected,
    required double size,
  }) {
    final isPhosphor = spec.id == _phosphorChannelId;
    final known = isPhosphor || EffectSpecs.byId(spec.id) != null;
    final setting = _effective.effect(spec.id);
    final iconSize = selected ? 20.0 : 12.0;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            key: ValueKey('effect-carousel-option-${spec.id}'),
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                key: ValueKey('effect-carousel-icon-${spec.id}'),
                width: iconSize,
                height: iconSize,
                child: _icon(
                  spec.pictogramId,
                  lit: selected && (isPhosphor || setting.enabled),
                  enabled: known,
                ),
              ),
              const SizedBox(width: 5),
              VfdLegend(
                spec.label,
                palette: _palette,
                lit: selected,
                size: size,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _controlDeck({
    required EffectSpec spec,
    required EffectSetting setting,
    required bool isPhosphor,
    required bool editable,
  }) => LayoutBuilder(
    key: ValueKey('effect-control-deck-${spec.id}'),
    builder: (context, constraints) {
      final controlHeight = isPhosphor
          ? PrismMetrics.height(PrismRole.compact)
          : 94.0;
      return Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            key: ValueKey('effect-control-${spec.id}'),
            width: constraints.maxWidth,
            height: controlHeight,
            child: isPhosphor
                ? _phosphorChoices(enabled: editable)
                : _strengthControl(
                    spec: spec,
                    setting: setting,
                    editable: editable,
                  ),
          ),
        ),
      );
    },
  );

  Widget _strengthControl({
    required EffectSpec spec,
    required EffectSetting setting,
    required bool editable,
  }) => MechanicalLever(
    key: ValueKey('effect-lever-${spec.id}'),
    label: '${spec.label} strength',
    value: setting.strength,
    min: 0,
    max: spec.maxStrength,
    precision: spec.precision,
    tickCount: 21,
    referenceValue: spec.defaultStrength,
    offAtMinimum: true,
    palette: _palette,
    prismStyle: widget.prismStyle,
    soundEnabled: widget.soundEnabled,
    hapticsEnabled: widget.hapticsEnabled,
    onChanged: editable
        ? (value) => _setEffect(spec, setting.withStrength(value, spec))
        : null,
  );

  Widget _phosphorChoices({required bool enabled}) {
    final selected = _effective.phosphorName;
    return LayoutBuilder(
      builder: (context, constraints) => FittedBox(
        alignment: Alignment.topCenter,
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: constraints.maxWidth,
          child: Row(
            children: <Widget>[
              for (var index = 0; index < Phosphor.all.length; index++) ...[
                if (index > 0) const SizedBox(width: 4),
                Expanded(
                  child: _phosphorButton(
                    key: ValueKey(
                      'service-effect-phosphor-${Phosphor.all[index].name}',
                    ),
                    label: Phosphor.all[index].name,
                    value: Phosphor.all[index].name,
                    enabled: enabled,
                    selected:
                        selected == Phosphor.all[index].name &&
                        (!widget.local ||
                            widget.overrides?.phosphorName ==
                                Phosphor.all[index].name),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _serviceButton({
    required Key key,
    required String label,
    required VoidCallback onPressed,
    bool enabled = true,
    bool lit = false,
  }) => PrismButton(
    key: key,
    label: label,
    palette: _palette,
    lit: lit,
    enabled: enabled,
    role: PrismRole.compact,
    style: widget.prismStyle,
    soundEnabled: widget.soundEnabled,
    hapticsEnabled: widget.hapticsEnabled,
    onPressed: enabled ? onPressed : null,
  );

  Widget _fitButton({
    required Key key,
    required String label,
    required VoidCallback? onPressed,
    bool lit = false,
    bool selected = false,
    PrismSpan span = PrismSpan.one,
    bool enabled = true,
  }) => FittedBox(
    fit: BoxFit.scaleDown,
    child: PrismButton(
      key: key,
      label: label,
      palette: _palette,
      lit: lit,
      selected: selected,
      enabled: enabled && onPressed != null,
      role: PrismRole.compact,
      span: span,
      style: widget.prismStyle,
      soundEnabled: widget.soundEnabled,
      hapticsEnabled: widget.hapticsEnabled,
      onPressed: enabled ? onPressed : null,
    ),
  );

  Widget _icon(String id, {required bool lit, bool enabled = true}) =>
      EffectPictogram(id: id, palette: _palette, lit: lit, enabled: enabled);

  bool _isOverridden(EffectSpec spec) => spec.id == _phosphorChannelId
      ? widget.overrides?.phosphorName != null
      : widget.overrides?.overrides(spec.id) ?? false;

  void _toggleOverride(EffectSpec spec, bool overridden) {
    if (spec.id == _phosphorChannelId) {
      _setOverrides(
        widget.overrides!.withPhosphor(
          overridden ? null : _effective.phosphorName,
        ),
      );
      return;
    }
    _setOverrides(
      widget.overrides!.withEffect(
        spec.id,
        overridden ? null : widget.baseProfile.effect(spec.id),
      ),
    );
  }

  void _setPhosphor(String? value) {
    if (widget.local) {
      _setOverrides(widget.overrides!.withPhosphor(value));
    } else if (value != null) {
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
    this.contentSafeInsets = EdgeInsets.zero,
    required this.onChanged,
  });

  final OpticalProfile profile;
  final PrismStyle style;
  final bool soundEnabled;
  final bool hapticsEnabled;
  final EdgeInsets contentSafeInsets;
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
    padding: EdgeInsets.fromLTRB(
      10,
      10,
      10,
      10 + widget.contentSafeInsets.bottom,
    ),
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
