import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/assistant_state.dart';
import 'package:personal_assistant/main.dart';
import 'package:personal_assistant/visual_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

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

  testWidgets('all three tactile theme choices apply and save immediately', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 260);
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

  test('each palette provides a distinct dark surface and orb spectrum', () {
    final palettes = FuturisticPalette.all;
    expect(palettes.map((p) => p.id), ['aurora', 'solar', 'deep_space']);
    expect(palettes.map((p) => p.darkBackground).toSet(), hasLength(3));
    expect(palettes.map((p) => p.primary).toSet(), hasLength(3));
    for (final palette in palettes) {
      expect(palette.orbColors, hasLength(4));
    }
  });
}
