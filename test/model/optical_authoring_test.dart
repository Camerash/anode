import 'dart:convert';
import 'dart:ui';

import 'package:anode/actions/action_registry.dart';
import 'package:anode/model/action_binding.dart';
import 'package:anode/model/component_instance.dart';
import 'package:anode/model/component_type.dart';
import 'package:anode/model/dashboard.dart';
import 'package:anode/model/design_layout.dart';
import 'package:anode/model/optical_profile.dart';
import 'package:anode/model/placement.dart';
import 'package:anode/model/settings.dart';
import 'package:anode/model/variant.dart';
import 'package:anode/model/vfd_module.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _reencode(Map<String, Object?> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, Object?>;

void main() {
  test('effect descriptions use clear operator instructions', () {
    expect(
      <String, String>{
        for (final spec in EffectSpecs.all) spec.id: spec.description,
      },
      <String, String>{
        EffectIds.emission: 'Set the light output of powered VFD segments.',
        EffectIds.bloom: 'Add a soft light halo around powered segments.',
        EffectIds.phosphorTexture:
            'Add small output differences across the phosphor layer.',
        EffectIds.gridMesh: 'Show the control-grid mesh in the VFD light.',
        EffectIds.unlitPhosphor:
            'Show the phosphor layer in segments that have no power.',
        EffectIds.phosphorDecay:
            'Keep a short afterglow when a segment powers down.',
        EffectIds.glassGrain:
            'Add fine glass and sensor noise across the VFD module.',
        EffectIds.filamentWires:
            'Show the cathode wires across the VFD module.',
        EffectIds.tiltParallax: 'Move the glass layer when the device tilts.',
      },
    );
    expect(
      EffectSpecs.storageSpec('future').description,
      'This effect is not available in this Anode version.',
    );
  });

  test('effect power preserves last non-zero strength', () {
    final spec = EffectSpecs.byId(EffectIds.bloom)!;
    final enabled = EffectSetting.at(1.42, spec);
    final disabled = enabled.toggled(spec);

    expect(disabled.strength, 0);
    expect(disabled.resumeStrength, 1.42);
    expect(disabled.toggled(spec).strength, 1.42);
    expect(disabled.withStrength(3, spec).strength, 2);
  });

  test('legacy Prism style values remain readable without migration', () {
    final style = PrismStyle.fromJson(<String, Object?>{
      'bevelDepth': 0.4,
      'faceOpacity': 0.2,
      'inactiveLuminosity': 1,
      'activeLuminosity': 0,
    });

    expect(style.bevelDepth, 0.4);
    expect(style.faceOpacity, 0.2);
    expect(style.inactiveLuminosity, 1);
    expect(style.activeLuminosity, 0);
    expect(style.toJson().keys, <String>[
      'bevelDepth',
      'faceOpacity',
      'inactiveLuminosity',
      'activeLuminosity',
    ]);
  });

  test('sparse optical inheritance resolves dashboard module component', () {
    final baseline = OpticalProfile(
      phosphorName: 'Cyan-green',
      effects: <String, EffectSetting>{
        EffectIds.bloom: const EffectSetting(
          strength: 0.8,
          resumeStrength: 0.8,
        ),
      },
    );
    final module = baseline.apply(
      OpticalOverrides(
        effects: <String, EffectSetting>{
          EffectIds.bloom: const EffectSetting(
            strength: 1.25,
            resumeStrength: 1.25,
          ),
        },
      ),
    );
    final component = module.apply(
      OpticalOverrides(
        phosphorName: 'Red',
        effects: <String, EffectSetting>{
          EffectIds.bloom: const EffectSetting(
            strength: 0,
            resumeStrength: 1.25,
          ),
        },
      ),
    );

    expect(module.phosphorName, 'Cyan-green');
    expect(module.effect(EffectIds.bloom).strength, 1.25);
    expect(component.phosphorName, 'Red');
    expect(component.effect(EffectIds.bloom).strength, 0);
  });

  test('effect scopes keep physical glass and motion at correct levels', () {
    expect(
      EffectSpecs.forScope(EffectScope.component).map((effect) => effect.id),
      isNot(contains(EffectIds.glassGrain)),
    );
    expect(
      EffectSpecs.forScope(EffectScope.component).map((effect) => effect.id),
      isNot(contains(EffectIds.filamentWires)),
    );
    expect(
      EffectSpecs.forScope(EffectScope.module).map((effect) => effect.id),
      containsAll(<String>[EffectIds.glassGrain, EffectIds.filamentWires]),
    );
    expect(
      EffectSpecs.forScope(EffectScope.module).map((effect) => effect.id),
      isNot(contains(EffectIds.tiltParallax)),
    );
  });

  test(
    'unknown effect, module, variant, action and params survive round trip',
    () {
      final original = ComponentInstance(
        id: 'future',
        typeId: ComponentTypes.prismButton,
        moduleId: 'module.from.future',
        variant: const VariantReference(id: 'prism.future', revision: 17),
        params: const <String, Object?>{'futureGeometry': 3.5},
        opticalOverrides: OpticalOverrides(
          effects: <String, EffectSetting>{
            'futureScatter': const EffectSetting(
              strength: 1.8,
              resumeStrength: 1.8,
            ),
          },
        ),
        actionBinding: ActionBinding(
          actionId: 'future.action',
          params: const <String, Object?>{'mode': 'turbo'},
        ),
      );

      final back = ComponentInstance.fromJson(_reencode(original.toJson()));

      expect(back.moduleId, 'module.from.future');
      expect(
        back.variant,
        const VariantReference(id: 'prism.future', revision: 17),
      );
      expect(back.params['futureGeometry'], 3.5);
      expect(back.opticalOverrides.effects['futureScatter']?.strength, 1.8);
      expect(back.actionBinding?.actionId, 'future.action');
      expect(back.actionBinding?.params['mode'], 'turbo');
    },
  );

  test('adding variants never removes legacy reference', () {
    const added = ComponentVariantSpec(
      reference: VariantReference(id: 'digits.round', revision: 1),
      displayName: 'Round',
      recommendedSize: Size(1, 0.5),
    );
    const type = ComponentTypeSpec(
      id: 'digits',
      displayName: 'Digits',
      capabilities: <Never>{},
      params: <Never>[],
      defaultSize: Size(0.8, 0.4),
      variants: <ComponentVariantSpec>[added],
    );

    expect(
      type.availableVariants.map((variant) => variant.reference),
      <VariantReference>[
        const VariantReference(id: 'digits.legacy', revision: 1),
        added.reference,
      ],
    );
  });

  test('deprecated variants remain renderable but leave new choices', () {
    const retired = ComponentVariantSpec(
      reference: VariantReference(id: 'digits.retired', revision: 2),
      displayName: 'Retired',
      recommendedSize: Size(1, 0.5),
      deprecated: true,
    );
    const type = ComponentTypeSpec(
      id: 'digits',
      displayName: 'Digits',
      capabilities: <Never>{},
      params: <Never>[],
      defaultSize: Size(0.8, 0.4),
      variants: <ComponentVariantSpec>[retired],
    );

    expect(type.variant(retired.reference), retired);
    expect(
      type.availableVariants.map((variant) => variant.reference),
      isNot(contains(retired.reference)),
    );
  });

  test('variant switching preserves authored placement size', () {
    final component = ComponentInstance(
      id: 'digits',
      typeId: ComponentTypes.speedDigits,
      placements: const <String, Placement>{
        'wide': Placement(center: Offset.zero, size: Size(1.4, 0.7)),
      },
    );

    final switched = component.copyWith(
      variant: const VariantReference(id: 'digits.round', revision: 3),
    );

    expect(switched.placements['wide']!.size, const Size(1.4, 0.7));
  });

  test('module normalization is flat and always provides implicit main', () {
    final modules = normaliseVfdModules(<VfdModule>[
      VfdModule(id: 'secondary', name: 'Secondary'),
      VfdModule(id: 'secondary', name: 'Duplicate'),
    ]);

    expect(modules.map((module) => module.id), <String>['main', 'secondary']);
  });

  test('removing a module reparents its components to main', () {
    final dashboard = Dashboard(
      id: 'modules',
      name: 'Modules',
      baseLayoutId: 'wide',
      layouts: const <DesignLayout>[
        DesignLayout(id: 'wide', frame: FrameSpec.aspect(2.6)),
      ],
      modules: <VfdModule>[VfdModule(id: 'secondary', name: 'Secondary')],
      components: <ComponentInstance>[
        ComponentInstance(
          id: 'bar',
          typeId: ComponentTypes.speedBar,
          moduleId: 'secondary',
        ),
      ],
    ).withoutModule('secondary');

    expect(dashboard.modules.map((module) => module.id), <String>['main']);
    expect(dashboard.components.single.moduleId, 'main');
  });

  test(
    'legacy settings payloads remain readable without authored app effects',
    () {
      final dashboard = DashboardSettings.fromJson(<String, Object?>{
        'brightness': 0.7,
        'phosphorName': 'Blue',
        'layers': <String, Object?>{'bloom': false, 'grain': false},
      });
      final global = GlobalSettings.fromJson(<String, Object?>{
        'demoMode': true,
        'layers': <String, Object?>{'bloom': false},
      });

      expect(dashboard.brightness, 0.7);
      expect(dashboard.phosphorName, 'Blue');
      expect(global.demoMode, isTrue);
      expect(global.toJson(), isNot(contains('layers')));
    },
  );

  test('editor dock preferences serialize directly and clamp alignment', () {
    final settings = GlobalSettings.fromJson(<String, Object?>{
      'editorDock': <String, Object?>{
        'portrait': <String, Object?>{'edge': 'right', 'alignment': -2},
        'landscape': <String, Object?>{'edge': 'left', 'alignment': 2},
      },
    });

    expect(
      settings.editorDock.portrait,
      const EditorDockPlacement(edge: EditorDockEdge.right, alignment: 0),
    );
    expect(
      settings.editorDock.landscape,
      const EditorDockPlacement(edge: EditorDockEdge.left, alignment: 1),
    );
    expect(
      GlobalSettings.fromJson(settings.toJson()).editorDock,
      settings.editorDock,
    );
  });

  test('authoring registry keeps unsupported platform actions visible', () {
    final registry = ActionRegistry.forAuthoring();

    expect(registry['anode.openLibrary']?.available, isTrue);
    expect(registry['media.playPause']?.available, isFalse);
    expect(registry['media.playPause']?.unavailableReason, isNotEmpty);
  });

  test('module regions remain independently authored per layout', () {
    final module = VfdModule(
      id: 'secondary',
      name: 'Secondary',
      regions: const <String, Placement>{
        'wide': Placement(center: Offset(0.4, 0), size: Size(0.8, 0.3)),
        'tall': Placement(center: Offset(0, -0.2), size: Size(0.3, 0.8)),
      },
    );
    final back = VfdModule.fromJson(_reencode(module.toJson()));

    expect(back.regions['wide']?.size, const Size(0.8, 0.3));
    expect(back.regions['tall']?.size, const Size(0.3, 0.8));
  });
}
