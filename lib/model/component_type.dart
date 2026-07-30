import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

import 'capability.dart';
import 'param_spec.dart';
import 'variant.dart';

/// A component type is data, not a widget and not a subclass. Everything the
/// rest of the app needs to know about a kind of component — what it needs from
/// the device, what can be tuned on it, how big it is — is declared here.
@immutable
class ComponentTypeSpec {
  const ComponentTypeSpec({
    required this.id,
    required this.displayName,
    required this.capabilities,
    required this.params,
    required this.defaultSize,
    this.description = '',
    this.variants = const <ComponentVariantSpec>[],
  });

  final String id;
  final String displayName;
  final String description;
  final Set<Capability> capabilities;
  final List<ParamSpec> params;
  final List<ComponentVariantSpec> variants;

  /// Nominal extent in design units at scale 1, for editor hit-testing.
  final Size defaultSize;

  VariantReference get legacyVariant =>
      VariantReference(id: '$id.legacy', revision: 1);

  ComponentVariantSpec get legacyVariantSpec => ComponentVariantSpec(
    reference: legacyVariant,
    displayName: 'Original',
    recommendedSize: defaultSize,
  );

  /// Legacy remains registered when later builds add variants. Removing it
  /// would turn every pre-variant dashboard into an unknown-reference fallback.
  List<ComponentVariantSpec> get registeredVariants {
    final declaredLegacy = variants.any(
      (candidate) => candidate.reference == legacyVariant,
    );
    return <ComponentVariantSpec>[
      if (!declaredLegacy) legacyVariantSpec,
      ...variants,
    ];
  }

  List<ComponentVariantSpec> get availableVariants => registeredVariants
      .where((candidate) => !candidate.deprecated)
      .toList(growable: false);

  ComponentVariantSpec? variant(VariantReference reference) {
    for (final candidate in registeredVariants) {
      if (candidate.reference == reference) return candidate;
    }
    return null;
  }

  List<ParamSpec> paramsFor(VariantReference reference) => <ParamSpec>[
    ...params,
    ...?variant(reference)?.params,
  ];

  ParamSpec? spec(String key, {VariantReference? variant}) {
    for (final p in paramsFor(variant ?? legacyVariant)) {
      if (p.key == key) return p;
    }
    return null;
  }

  Map<String, Object?> get defaults => <String, Object?>{
    for (final p in params) p.key: p.defaultValue,
  };

  /// Fills in missing params and coerces known ones. Unknown keys are kept
  /// verbatim so a dashboard written by a newer build survives a round trip
  /// through an older one.
  Map<String, Object?> normalise(
    Map<String, Object?> raw, {
    VariantReference? variant,
  }) {
    final out = <String, Object?>{...raw};
    for (final p in paramsFor(variant ?? legacyVariant)) {
      out[p.key] = p.coerce(
        raw.containsKey(p.key) ? raw[p.key] : p.defaultValue,
      );
    }
    return out;
  }
}

/// The registry of shipped component types.
///
/// Types listed here that the renderer cannot yet draw are declarations, not
/// promises: the renderer skips ids it does not implement. They are not inert
/// decoration — each one is backed by a real device value.
abstract final class ComponentTypes {
  static const String speedDigits = 'speedDigits';
  static const String speedBar = 'speedBar';
  static const String unitLegend = 'unitLegend';
  static const String outsideTemp = 'outsideTemp';
  static const String phoneBattery = 'phoneBattery';
  static const String altitude = 'altitude';
  static const String prismButton = 'prismButton';

  static const List<ComponentTypeSpec> all = <ComponentTypeSpec>[
    ComponentTypeSpec(
      id: speedDigits,
      displayName: 'Speed digits',
      description: 'Segmented numeric speed readout.',
      capabilities: <Capability>{Capability.gps},
      // Width is digit advance * default digit count; height is the glyph's
      // 1.4-unit local extent at the tuned digit scale. These reproduce the
      // authored layout exactly at the default param values.
      defaultSize: Size(1.035, 0.588),
      params: <ParamSpec>[
        ParamSpec(
          key: 'digits',
          label: 'Digit count',
          type: ParamType.integer,
          defaultValue: 3,
          min: 1,
          max: 4,
        ),
        ParamSpec(
          key: 'unit',
          label: 'Unit',
          type: ParamType.option,
          defaultValue: 'kph',
          options: <String>['kph', 'mph'],
          optionLabels: <String, String>{'kph': 'KM/H', 'mph': 'MPH'},
        ),
        ParamSpec(
          key: 'blankLeadingZeros',
          label: 'Blank leading zeros',
          type: ParamType.boolean,
          defaultValue: true,
        ),
      ],
    ),
    ComponentTypeSpec(
      id: speedBar,
      displayName: 'Speed bar',
      description: 'Cell bar showing speed against a chosen maximum.',
      capabilities: <Capability>{Capability.gps},
      defaultSize: Size(1.96, 0.084),
      params: <ParamSpec>[
        ParamSpec(
          key: 'cells',
          label: 'Cells',
          type: ParamType.integer,
          defaultValue: 20,
          min: 4,
          max: 40,
        ),
        ParamSpec(
          key: 'maxKph',
          label: 'Full scale (kph)',
          type: ParamType.number,
          defaultValue: 260.0,
          min: 20,
          max: 400,
          step: 5,
          precision: 0,
          unitSuffix: 'km/h',
        ),
      ],
    ),
    ComponentTypeSpec(
      id: unitLegend,
      displayName: 'Unit legend',
      description: 'KM/H and MPH annunciator.',
      capabilities: <Capability>{},
      // Encloses both stacked lines: one cap height plus the line separation.
      defaultSize: Size(0.203, 0.242),
      params: <ParamSpec>[
        ParamSpec(
          key: 'stacked',
          label: 'Stacked',
          type: ParamType.boolean,
          defaultValue: true,
        ),
      ],
    ),
    ComponentTypeSpec(
      id: outsideTemp,
      displayName: 'Outside temperature',
      description: 'External air-temperature readout.',
      capabilities: <Capability>{Capability.gps, Capability.network},
      defaultSize: Size(0.55, 0.22),
      params: <ParamSpec>[
        ParamSpec(
          key: 'unit',
          label: 'Unit',
          type: ParamType.option,
          defaultValue: 'celsius',
          options: <String>['celsius', 'fahrenheit'],
        ),
      ],
    ),
    ComponentTypeSpec(
      id: phoneBattery,
      displayName: 'Battery gauge',
      description: 'Phone battery-level indicator.',
      capabilities: <Capability>{Capability.battery},
      defaultSize: Size(0.62, 0.12),
      params: <ParamSpec>[
        ParamSpec(
          key: 'lowWarningPercent',
          label: 'Low warning at',
          type: ParamType.integer,
          defaultValue: 15,
          min: 5,
          max: 50,
        ),
      ],
    ),
    ComponentTypeSpec(
      id: altitude,
      displayName: 'Altitude',
      description: 'Barometric altitude readout.',
      capabilities: <Capability>{Capability.barometer},
      defaultSize: Size(0.62, 0.22),
      params: <ParamSpec>[
        ParamSpec(
          key: 'unit',
          label: 'Unit',
          type: ParamType.option,
          defaultValue: 'metres',
          options: <String>['metres', 'feet'],
        ),
      ],
    ),
    ComponentTypeSpec(
      id: prismButton,
      displayName: 'Prism button',
      description: 'Interactive smoked-acrylic switch.',
      capabilities: <Capability>{},
      defaultSize: Size(0.42, 0.18),
      params: <ParamSpec>[
        ParamSpec(
          key: 'label',
          label: 'Label',
          type: ParamType.text,
          defaultValue: 'ACTION',
        ),
        ParamSpec(
          key: 'lit',
          label: 'Light',
          type: ParamType.boolean,
          defaultValue: false,
        ),
      ],
    ),
  ];

  static ComponentTypeSpec? byId(String id) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }
}
