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
            .widget<AnimatedContainer>(
              find.byKey(const ValueKey('dock-selection-home')),
            )
            .duration,
        const Duration(milliseconds: 240),
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
        const Duration(milliseconds: 240),
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      state.dispose();
    },
  );

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
