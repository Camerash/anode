import 'package:flutter/foundation.dart';

import 'capability.dart';
import 'param_spec.dart';

@immutable
class ActionBinding {
  ActionBinding({
    required this.actionId,
    Map<String, Object?> params = const <String, Object?>{},
  }) : params = Map<String, Object?>.unmodifiable(params);

  final String actionId;
  final Map<String, Object?> params;

  Map<String, Object?> toJson() => <String, Object?>{
    'actionId': actionId,
    'params': params,
  };

  factory ActionBinding.fromJson(Map<String, Object?> json) => ActionBinding(
    actionId: json['actionId'] as String? ?? '',
    params:
        (json['params'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{},
  );
}

@immutable
class ActionSpec {
  const ActionSpec({
    required this.id,
    required this.label,
    required this.description,
    this.capabilities = const <Capability>{},
    this.params = const <ParamSpec>[],
  });

  final String id;
  final String label;
  final String description;
  final Set<Capability> capabilities;
  final List<ParamSpec> params;
}

abstract final class ActionSpecs {
  static const List<ActionSpec> all = <ActionSpec>[
    ActionSpec(
      id: 'anode.openLibrary',
      label: 'Open library',
      description: 'Open Anode designs and device settings.',
    ),
    ActionSpec(
      id: 'anode.toggleDemo',
      label: 'Toggle demo',
      description: 'Start or stop simulated dashboard data.',
    ),
    ActionSpec(
      id: 'media.playPause',
      label: 'Play / pause',
      description: 'Toggle media playback when supported by the platform.',
      capabilities: <Capability>{Capability.mediaControl},
    ),
    ActionSpec(
      id: 'media.previous',
      label: 'Previous track',
      description: 'Move to the previous media item when supported.',
      capabilities: <Capability>{Capability.mediaControl},
    ),
    ActionSpec(
      id: 'media.next',
      label: 'Next track',
      description: 'Move to the next media item when supported.',
      capabilities: <Capability>{Capability.mediaControl},
    ),
  ];

  static ActionSpec? byId(String id) {
    for (final spec in all) {
      if (spec.id == id) return spec;
    }
    return null;
  }
}
