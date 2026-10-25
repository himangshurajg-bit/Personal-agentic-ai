import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/assistant_state.dart';
import 'package:personal_assistant/main.dart';
import 'package:personal_assistant/visual_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AssistantState.device, (call) async {
          if (call.method == 'get_launcher_icon') return null;
          throw MissingPluginException(
            'Unexpected device call: ${call.method}',
          );
        });
  });

  test('Aurora is the default and selected palette persists', () async {
    final first = AssistantState();
    await first.initialize();
    expect(first.visualTheme, 'aurora');

    await first.setVisualTheme('solar');
    expect(await first.storage.read(key: 'visual_theme'), 'solar');
    first.dispose();

    final reopened = AssistantState();
    await reopened.initialize();
    expect(reopened.visualTheme, 'solar');
    await expectLater(
      reopened.setVisualTheme('not-a-theme'),
      throwsArgumentError,
    );
    reopened.dispose();
  });

  testWidgets('all five tactile theme choices apply and save immediately', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = AssistantState();
    await state.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 380,
              child: AnimatedBuilder(
                animation: state,
                builder: (context, _) => FuturisticThemePicker(state: state),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Aurora'), findsOneWidget);
    expect(find.text('Solar'), findsOneWidget);
    expect(find.text('Deep Space'), findsOneWidget);
    expect(find.text('Forest'), findsOneWidget);
    expect(find.text('Crimson'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('theme-choice-forest')));
    await tester.pumpAndSettle();
    expect(state.visualTheme, 'forest');
    expect(await state.storage.read(key: 'visual_theme'), 'forest');
    expect(
      tester.getSemantics(find.byKey(const ValueKey('theme-choice-forest'))),
      matchesSemantics(
        isButton: true,
        label: 'Forest, Forest green · moss, selected',
        hasSelectedState: true,
        isSelected: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('theme-choice-crimson')));
    await tester.pumpAndSettle();
    expect(state.visualTheme, 'crimson');
    expect(await state.storage.read(key: 'visual_theme'), 'crimson');

    await tester.tap(find.byKey(const ValueKey('theme-choice-solar')));
    await tester.pumpAndSettle();
    expect(state.visualTheme, 'solar');
    expect(await state.storage.read(key: 'visual_theme'), 'solar');
    expect(
      tester.getSemantics(find.byKey(const ValueKey('theme-choice-solar'))),
      matchesSemantics(
        isButton: true,
        label: 'Solar, Amber · coral, selected',
        hasSelectedState: true,
        isSelected: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets('glass controls keep clear feedback and honor reduced motion', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    final state = AssistantState();
    await state.initialize();
    await tester.pumpWidget(AssistantApp(state: state));

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    final theme = app.theme!;
    final emptyStates = const <WidgetState>{};
    final pressed = const <WidgetState>{WidgetState.pressed};
    expect(app.themeAnimationDuration, Duration.zero);
    expect(theme.outlinedButtonTheme.style!.animationDuration, Duration.zero);
    expect(theme.textButtonTheme.style!.animationDuration, Duration.zero);
    expect(theme.iconButtonTheme.style!.animationDuration, Duration.zero);
    expect(
      theme.outlinedButtonTheme.style!.side!.resolve(emptyStates),
      isNotNull,
    );
    expect(
      theme.outlinedButtonTheme.style!.overlayColor!.resolve(pressed),
      isNotNull,
    );
    expect(theme.iconButtonTheme.style!.side!.resolve(emptyStates), isNotNull);
    expect(theme.listTileTheme.shape, isA<RoundedRectangleBorder>());
    expect(theme.cardTheme.shape, isA<RoundedRectangleBorder>());
    expect(
      theme.switchTheme.trackOutlineColor!.resolve(emptyStates),
      isNotNull,
    );

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures();
    await tester.pump();
    final animatedApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(
      animatedApp.themeAnimationDuration,
      const Duration(milliseconds: 520),
    );
    expect(
      animatedApp.theme!.outlinedButtonTheme.style!.animationDuration,
      const Duration(milliseconds: 180),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  test('each palette provides a distinct dark surface and orb spectrum', () {
    final palettes = FuturisticPalette.all;
    expect(palettes.map((p) => p.id), [
      'aurora',
      'solar',
      'deep_space',
      'forest',
      'crimson',
    ]);
    expect(palettes.map((p) => p.darkBackground).toSet(), hasLength(5));
    expect(palettes.map((p) => p.primary).toSet(), hasLength(5));
    expect(
      FuturisticPalette.fromId('forest').darkBackground,
      const Color(0xff101812),
    );
    expect(
      FuturisticPalette.fromId('forest').description,
      'Forest green · moss',
    );
    expect(
      FuturisticPalette.fromId('crimson').primary.r,
      greaterThan(FuturisticPalette.fromId('crimson').primary.g),
    );
    for (final palette in palettes) {
      expect(palette.orbColors, hasLength(4));
    }
  });
}
