import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

import 'capability.dart';
import 'param_spec.dart';

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
  });

  final String id;
  final String displayName;
  final Set<Capability> capabilities;
  final List<ParamSpec> params;

  /// Nominal extent in design units at scale 1, for editor hit-testing.
  final Size defaultSize;

  ParamSpec? spec(String key) {
    for (final p in params) {
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
  Map<String, Object?> normalise(Map<String, Object?> raw) {
    final out = <String, Object?>{...raw};
    for (final p in params) {
      out[p.key] = p.coerce(raw.containsKey(p.key) ? raw[p.key] : p.defaultValue);
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

  static const List<ComponentTypeSpec> all = <ComponentTypeSpec>[
    ComponentTypeSpec(
      id: speedDigits,
      displayName: 'Speed digits',
      capabilities: <Capability>{Capability.gps},
      defaultSize: Size(1.04, 0.84),
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
        ),
      ],
    ),
    ComponentTypeSpec(
      id: unitLegend,
      displayName: 'Unit legend',
      capabilities: <Capability>{},
      defaultSize: Size(0.21, 0.19),
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
  ];

  static ComponentTypeSpec? byId(String id) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }
}
