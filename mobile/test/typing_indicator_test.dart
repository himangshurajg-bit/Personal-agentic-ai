import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/typing_indicator.dart';

void main() {
  testWidgets('glass typing indicator has three dots and pulses', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: false),
          child: Scaffold(body: GlassTypingIndicator()),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Assistant is typing'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      expect(find.byKey(ValueKey('typing-dot-$i')), findsOneWidget);
    }

    final before = tester
        .widget<Transform>(find.byKey(const ValueKey('typing-scale-0')))
        .transform
        .storage[0];
    await tester.pump(const Duration(milliseconds: 220));
    final after = tester
        .widget<Transform>(find.byKey(const ValueKey('typing-scale-0')))
        .transform
        .storage[0];
    expect(after, isNot(before));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('respects reduced motion', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: GlassTypingIndicator()),
        ),
      ),
    );

    final before = tester
        .widget<Transform>(find.byKey(const ValueKey('typing-scale-0')))
        .transform
        .storage[0];
    await tester.pump(const Duration(milliseconds: 700));
    final after = tester
        .widget<Transform>(find.byKey(const ValueKey('typing-scale-0')))
        .transform
        .storage[0];
    expect(after, before);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
