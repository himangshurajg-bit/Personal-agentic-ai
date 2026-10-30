import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/assistant_features_screen.dart';
import 'package:personal_assistant/assistant_state.dart';
import 'package:personal_assistant/user_notification_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('personal_assistant/device');
  final calls = <MethodCall>[];
  var permissionGranted = true;

  setUp(() {
    calls.clear();
    permissionGranted = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'request_access_permission') {
            return <String, Object?>{
              'permission': 'notifications',
              'granted': permissionGranted,
              'required': true,
            };
          }
          if (call.method == 'post_user_notification') {
            return <String, Object?>{'posted': true};
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('content bounds and control characters match Android parser', () {
    expect(isValidUserNotificationContent('Title', 'hello\nworld\t!'), isTrue);
    expect(isValidUserNotificationContent(' ', 'body'), isFalse);
    expect(isValidUserNotificationContent('Title\nline', 'body'), isFalse);
    expect(isValidUserNotificationContent('Title', 'body\u0000'), isFalse);
    expect(isValidUserNotificationContent(List.filled(81, 'x').join(), 'body'), isFalse);
    expect(isValidUserNotificationContent('Title', List.filled(301, 'x').join()), isFalse);
  });

  Future<void> openComposer(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FeaturesScreen(
          state: AssistantState(),
          onReminder: (context, value) async {},
          initialTab: 15,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('user-notification-title')), 'Study check-in');
    await tester.enterText(find.byKey(const Key('user-notification-text')), 'Review the mock test at 7 PM.');
    await tester.pump();
  }

  testWidgets('opening or canceling review never requests permission or posts', (
    tester,
  ) async {
    await openComposer(tester);
    expect(calls, isEmpty);
    await tester.ensureVisible(find.byKey(const Key('review-user-notification')));
    await tester.tap(find.byKey(const Key('review-user-notification')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Title: Study check-in'), findsOneWidget);
    expect(calls, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
  });

  testWidgets('posts only after exact review and permission approval', (
    tester,
  ) async {
    await openComposer(tester);
    await tester.ensureVisible(find.byKey(const Key('review-user-notification')));
    await tester.tap(find.byKey(const Key('review-user-notification')));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    await tester.tap(find.text('Post notification'));
    await tester.pumpAndSettle();

    expect(calls.map((call) => call.method), [
      'request_access_permission',
      'post_user_notification',
    ]);
    expect(calls.first.arguments, {'permission': 'notifications'});
    expect(calls.last.arguments, {
      'title': 'Study check-in',
      'text': 'Review the mock test at 7 PM.',
    });
    expect(find.textContaining('Android accepted the notification request'), findsOneWidget);
  });

  testWidgets('denied notification permission prevents posting', (tester) async {
    permissionGranted = false;
    await openComposer(tester);
    await tester.ensureVisible(find.byKey(const Key('review-user-notification')));
    await tester.tap(find.byKey(const Key('review-user-notification')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Post notification'));
    await tester.pumpAndSettle();

    expect(calls.map((call) => call.method), ['request_access_permission']);
    expect(find.textContaining('permission was not granted'), findsOneWidget);
  });
}
