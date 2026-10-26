import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/assistant_state.dart';
import 'package:personal_assistant/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_tts'),
          (_) async => 1,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AssistantState.device, (_) async => true);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'), null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AssistantState.device, null);
  });

  testWidgets(
    'glass dock is exposed as a selected, animated navigation button',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: false);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      tester.view.physicalSize = const Size(382, 754);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final state = AssistantState()
        ..ready = true
        ..appLockConfigurationReady = true
        ..onboarded = true;
      await state.local.load();
      await tester.pumpWidget(AssistantApp(state: state));
      // The home surface itself has a repeating visual, so use a fixed settle step.
      await tester.pump(const Duration(milliseconds: 600));

      expect(
        find.byKey(const ValueKey('assistant-dock-glass')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('assistant-dock-backdrop')),
        findsOneWidget,
      );
      final home = tester.getSemantics(
        find.byKey(const ValueKey('dock-item-home')),
      );
      expect(home.getSemanticsData().label, 'Home');
      expect(home.getSemanticsData().flagsCollection.isButton, isTrue);
      expect(
        home.getSemanticsData().flagsCollection.isSelected,
        ui.Tristate.isTrue,
      );
      expect(home.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(
        tester
            .widget<AnimatedAlign>(
              find.byKey(const ValueKey('dock-liquid-glass')),
            )
            .duration,
        const Duration(milliseconds: 360),
      );
      expect(
        tester
            .widget<AnimatedContainer>(
              find.byKey(const ValueKey('dock-liquid-glass-surface')),
            )
            .duration,
        const Duration(milliseconds: 360),
      );
      expect(
        tester
            .widget<AnimatedContainer>(
              find.byKey(const ValueKey('dock-selection-home')),
            )
            .duration,
        const Duration(milliseconds: 360),
      );
      expect(
        tester
            .widget<AnimatedSwitcher>(
              find.descendant(
                of: find.byKey(const ValueKey('dock-item-home')),
                matching: find.byType(AnimatedSwitcher),
              ),
            )
            .duration,
        const Duration(milliseconds: 360),
      );
      expect(tester.takeException(), isNull);

      final startCenter = tester.getCenter(
        find.byKey(const ValueKey('dock-liquid-glass-surface')),
      );
      await tester.tap(find.byKey(const ValueKey('dock-item-memory')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final middleCenter = tester.getCenter(
        find.byKey(const ValueKey('dock-liquid-glass-surface')),
      );
      expect(middleCenter.dx, isNot(startCenter.dx));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester
            .widget<AnimatedAlign>(
              find.byKey(const ValueKey('dock-liquid-glass')),
            )
            .alignment,
        const Alignment(.5, 0),
      );
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('dock-item-memory')))
            .getSemanticsData()
            .flagsCollection
            .isSelected,
        ui.Tristate.isTrue,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      state.dispose();
    },
  );

  testWidgets(
    'glass selection is centered on every dock destination and alias',
    (tester) async {
      tester.view.physicalSize = const Size(382, 754);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const routes = <String, int>{
        '/': 0,
        '/home': 0,
        '/features': 0,
        '/features/research': 0,
        '/chat': 1,
        '/voice': 2,
        '/task-voice': 2,
        '/memory': 3,
        '/library': 3,
        '/files': 3,
        '/settings': 4,
        '/connections': 4,
        '/study': 0,
        '/whiteboard': 0,
        '/automations': 0,
        '/drafts': 0,
        '/skills': 0,
        '/images': 0,
      };
      const labels = ['Home', 'Chat', 'Voice', 'Memory', 'Settings'];

      for (final entry in routes.entries) {
        await tester.pumpWidget(_dockHarness(entry.key));
        await tester.pump();
        final index = entry.value;
        final selection = find.byKey(
          const ValueKey('dock-liquid-glass-surface'),
        );
        final destination = find.byKey(
          ValueKey('dock-item-${labels[index].toLowerCase()}'),
        );
        final selectionCenter = tester.getCenter(selection);
        final destinationCenter = tester.getCenter(destination);

        expect(
          selectionCenter.dx,
          closeTo(destinationCenter.dx, 1),
          reason: 'glass should center on ${labels[index]} for ${entry.key}',
        );
        expect(
          tester
              .getSemantics(destination)
              .getSemanticsData()
              .flagsCollection
              .isSelected,
          ui.Tristate.isTrue,
          reason:
              '${labels[index]} should be announced selected for ${entry.key}',
        );
        expect(tester.takeException(), isNull);
      }

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('voice destination gets selected semantics and an animated mic', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: false);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    tester.view.physicalSize = const Size(382, 754);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_dockHarness('/voice'));
    await tester.pump();

    final voice = find.byKey(const ValueKey('dock-item-voice'));
    expect(
      tester.getSemantics(voice).getSemanticsData().flagsCollection.isSelected,
      ui.Tristate.isTrue,
    );
    expect(
      tester
          .widget<AnimatedAlign>(
            find.byKey(const ValueKey('dock-liquid-glass')),
          )
          .alignment,
      Alignment.center,
    );
    expect(
      tester
          .widget<AnimatedScale>(find.byKey(const ValueKey('dock-voice-scale')))
          .scale,
      1.08,
    );
    await tester.pump(const Duration(milliseconds: 360));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('dock selection stops animating when reduced motion is enabled', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    tester.view.physicalSize = const Size(382, 754);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = AssistantState()
      ..ready = true
      ..appLockConfigurationReady = true
      ..onboarded = true;
    await state.local.load();
    await tester.pumpWidget(AssistantApp(state: state));

    expect(
      tester
          .widget<AnimatedAlign>(
            find.byKey(const ValueKey('dock-liquid-glass')),
          )
          .duration,
      Duration.zero,
    );
    expect(
      tester
          .widget<AnimatedContainer>(
            find.byKey(const ValueKey('dock-liquid-glass-surface')),
          )
          .duration,
      Duration.zero,
    );
    final glassHero = tester.widget<Hero>(
      find.byKey(const ValueKey('dock-liquid-glass-hero')),
    );
    expect(glassHero.tag, isNot('assistant-dock-liquid-glass-selection'));
    expect(
      tester
          .widget<AnimatedContainer>(
            find.byKey(const ValueKey('dock-selection-home')),
          )
          .duration,
      Duration.zero,
    );
    expect(
      tester
          .widget<AnimatedSwitcher>(
            find.descendant(
              of: find.byKey(const ValueKey('dock-item-home')),
              matching: find.byType(AnimatedSwitcher),
            ),
          )
          .duration,
      Duration.zero,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    state.dispose();
  });
}

Widget _dockHarness(String route) {
  Widget page() => Shell(title: 'Dock test', child: const SizedBox.shrink());

  return MaterialApp(
    key: ValueKey('dock-harness-$route'),
    onGenerateInitialRoutes: (initialRoute) => [
      MaterialPageRoute<void>(
        settings: RouteSettings(name: initialRoute),
        builder: (_) => page(),
      ),
    ],
    onGenerateRoute: (settings) =>
        MaterialPageRoute<void>(settings: settings, builder: (_) => page()),
    initialRoute: route,
  );
}
