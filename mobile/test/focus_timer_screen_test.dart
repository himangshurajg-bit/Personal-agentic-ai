import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/assistant_features_screen.dart';
import 'package:personal_assistant/assistant_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('focus timer controls persist only an on-device deadline', (
    tester,
  ) async {
    final state = AssistantState();
    await state.local.load();
    await tester.pumpWidget(
      MaterialApp(
        home: FeaturesScreen(
          state: state,
          initialTab: 6,
          onReminder: (context, value) async {},
        ),
      ),
    );

    expect(
      find.text('A 25-minute focus session and a 5-minute break.'),
      findsOneWidget,
    );
    expect(find.text('25:00'), findsOneWidget);

    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(find.text('Pause'), findsOneWidget);
    final saved = state.local.snapshot['focus_timer'] as Map;
    expect(saved['phase'], 'focus');
    expect(saved['deadline_utc'], isA<String>());
    expect(saved['remaining_seconds'], 25 * 60);

    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();
    expect(find.text('Start'), findsOneWidget);
    expect(
      (state.local.snapshot['focus_timer'] as Map)['deadline_utc'],
      isNull,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('does not run a background service'),
      findsOneWidget,
    );
  });
}
