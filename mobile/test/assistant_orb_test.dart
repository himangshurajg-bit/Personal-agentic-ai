import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/ui_motion.dart';

void main() {
  testWidgets('assistant orb renders and announces its active state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: HolographicAssistantOrb(
              state: HolographicOrbState.listening,
              size: 128,
              audioLevel: 7,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.bySemanticsLabel('Assistant is listening'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('orb respects reduced motion and ticker-off modes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: const TickerMode(
          enabled: false,
          child: MaterialApp(
            home: Scaffold(
              body: HolographicAssistantOrb(
                state: HolographicOrbState.thinking,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 3));

    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.bySemanticsLabel('Assistant is thinking'), findsOneWidget);
  });
}
