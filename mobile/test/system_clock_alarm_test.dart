import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/assistant_features_screen.dart';
import 'package:personal_assistant/assistant_state.dart';
import 'package:personal_assistant/system_clock_alarm_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('personal_assistant/device');

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  testWidgets('alarm tool explains Clock confirmation and opens the picker', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SystemClockAlarmScreen())),
    );
    expect(find.text('System Clock alarm'), findsOneWidget);
    expect(find.textContaining('not saved until you confirm'), findsOneWidget);
    await tester.tap(find.text('Choose and review alarm'));
    await tester.pumpAndSettle();
    expect(find.text('Choose alarm time'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Review alarm'), findsNothing);
  });

  testWidgets('alarm tool appears in Assistant tools', (tester) async {
    final state = AssistantState();
    await tester.pumpWidget(
      MaterialApp(
        home: FeaturesScreen(
          state: state,
          onReminder: _ignoreReminder,
          initialTab: 10,
        ),
      ),
    );
    expect(find.text('System Clock alarm'), findsOneWidget);
  });
}

Future<void> _ignoreReminder(BuildContext context, String value) async {}
