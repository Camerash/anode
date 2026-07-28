import 'dart:async';

import '../model/action_binding.dart';

typedef ActionHandler = FutureOr<void> Function(ActionBinding binding);

class RegisteredAction {
  const RegisteredAction({
    required this.spec,
    required this.available,
    this.unavailableReason,
    this.handler,
  });

  final ActionSpec spec;
  final bool available;
  final String? unavailableReason;
  final ActionHandler? handler;

  Future<void> invoke(ActionBinding binding) async {
    if (!available || handler == null) return;
    await handler!(binding);
  }
}

class ActionRegistry {
  ActionRegistry(Iterable<RegisteredAction> actions)
    : _actions = <String, RegisteredAction>{
        for (final action in actions) action.spec.id: action,
      };

  final Map<String, RegisteredAction> _actions;

  RegisteredAction? operator [](String id) => _actions[id];
  Iterable<RegisteredAction> get actions => _actions.values;

  Future<void> invoke(ActionBinding binding) async {
    await _actions[binding.actionId]?.invoke(binding);
  }

  factory ActionRegistry.forCluster({
    required void Function() onOpenLibrary,
    required void Function() onToggleDemo,
  }) {
    ActionSpec spec(String id) => ActionSpecs.byId(id)!;
    return ActionRegistry(<RegisteredAction>[
      RegisteredAction(
        spec: spec('anode.openLibrary'),
        available: true,
        handler: (_) => onOpenLibrary(),
      ),
      RegisteredAction(
        spec: spec('anode.toggleDemo'),
        available: true,
        handler: (_) => onToggleDemo(),
      ),
      for (final id in <String>[
        'media.playPause',
        'media.previous',
        'media.next',
      ])
        RegisteredAction(
          spec: spec(id),
          available: false,
          unavailableReason:
              'No app-owned media session is registered on this platform.',
        ),
    ]);
  }

  /// Registry view used while authoring. App-owned actions can be selected;
  /// platform integrations remain visible but explicitly unavailable.
  factory ActionRegistry.forAuthoring() {
    ActionSpec spec(String id) => ActionSpecs.byId(id)!;
    return ActionRegistry(<RegisteredAction>[
      for (final id in <String>['anode.openLibrary', 'anode.toggleDemo'])
        RegisteredAction(spec: spec(id), available: true),
      for (final id in <String>[
        'media.playPause',
        'media.previous',
        'media.next',
      ])
        RegisteredAction(
          spec: spec(id),
          available: false,
          unavailableReason:
              'Unavailable until Anode owns a compatible media session.',
        ),
    ]);
  }
}
