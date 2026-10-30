import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/assistant_features_screen.dart';
import 'package:personal_assistant/assistant_state.dart';
import 'package:personal_assistant/system_clock_timer.dart';
import 'package:personal_assistant/system_clock_timer_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('personal_assistant/device');

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test('duration parser accepts boundaries and optional labels', () {
    expect(parseSystemClockTimerRequest('1', '')?.seconds, 1);
    expect(parseSystemClockTimerRequest(' 86400 ', ' tea ')?.label, 'tea');
    expect(parseSystemClockTimerRequest('60', '')?.label, isEmpty);
  });

  test('spoken timer shortcut requires a direct single exact duration', () {
    expect(
      parseExplicitSpokenTimerCommand('Set a timer for 5 minutes')?.seconds,
      300,
    );
    expect(
      parseExplicitSpokenTimerCommand('Please start a timer for 90 seconds')
          ?.seconds,
      90,
    );
    expect(
      parseExplicitSpokenTimerCommand('Create a timer of 2 hours')?.seconds,
      7200,
    );
    for (final phrase in [
      'What is a timer for 5 minutes?',
      'If I ask, set a timer for 5 minutes',
      'Do not set a timer for 5 minutes',
      'Set a timer for 5 minutes tomorrow',
      'Set a timer for 5 minutes or 10 minutes',
      'Set a repeating timer for 5 minutes',
      'Set an alarm for 7:30 and a timer for 5 minutes',
      'Set a timer for 25 hours',
      'Set a timer for 5 minutes for tea',
      'Could you set a timer for 5 minutes',
    ]) {
      expect(parseExplicitSpokenTimerCommand(phrase), isNull, reason: phrase);
    }
  });

  test('duration parser rejects malformed values and unsafe labels', () {
    for (final value in ['0', '86401', '-2', '1.5', '1e2', '', '1000000']) {
      expect(parseSystemClockTimerRequest(value, ''), isNull, reason: value);
    }
    expect(parseSystemClockTimerRequest('60', 'x' * 41), isNull);
    expect(parseSystemClockTimerRequest('60', 'tea\nbreak'), isNull);
  });

  testWidgets('invalid duration does not request a system timer', (
    tester,
  ) async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls++;
          return null;
        });
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SystemClockTimerScreen())),
    );
    await tester.enterText(find.byKey(const Key('system-clock-seconds')), '0');
    await tester.tap(find.text('Open Clock timer'));
    await tester.pump();
    expect(calls, 0);
    expect(find.textContaining('1–86,400'), findsOneWidget);
  });

  testWidgets('valid duration hands off to Clock and does not claim started', (
    tester,
  ) async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          received = call;
          return true;
        });
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SystemClockTimerScreen())),
    );
    await tester.enterText(
      find.byKey(const Key('system-clock-seconds')),
      '300',
    );
    await tester.enterText(
      find.byKey(const Key('system-clock-label')),
      'tea break',
    );
    await tester.tap(find.text('Open Clock timer'));
    await tester.pumpAndSettle();

    expect(received?.method, 'set_system_timer');
    expect(received?.arguments, {'seconds': 300, 'label': 'tea break'});
    expect(
      find.text('Clock opened. Review and start the timer there.'),
      findsOneWidget,
    );
    expect(find.text('Timer started'), findsNothing);
  });

  testWidgets('unavailable system Clock is reported without success', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(
            code: 'unavailable',
            message: 'No Android Clock app can handle timer requests',
          );
        });
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SystemClockTimerScreen())),
    );
    await tester.enterText(find.byKey(const Key('system-clock-seconds')), '60');
    await tester.tap(find.text('Open Clock timer'));
    await tester.pumpAndSettle();

    expect(
      find.text('No Android Clock app can handle timer requests'),
      findsOneWidget,
    );
    expect(
      find.text('Clock opened. Review and start the timer there.'),
      findsNothing,
    );
  });

  testWidgets('timer feature is a separate assistant-tools tab', (
    tester,
  ) async {
    final state = AssistantState();
    await state.local.load();
    await tester.pumpWidget(
      MaterialApp(
        home: FeaturesScreen(
          state: state,
          onReminder: _ignoreReminder,
          initialTab: 9,
        ),
      ),
    );
    expect(find.text('System Clock timer'), findsOneWidget);
  });
}

Future<void> _ignoreReminder(BuildContext context, String value) async {}
