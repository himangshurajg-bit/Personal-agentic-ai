import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:personal_assistant/assistant_state.dart';
import 'package:personal_assistant/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final channel = AssistantState.device;
  final pendingCalls = <MethodCall>[];
  final requested = <String>[];
  var status = <String, dynamic>{
    'sdk': 36,
    'microphone_granted': false,
    'notifications_granted': false,
  };

  setUp(() {
    pendingCalls.clear();
    requested.clear();
    status = {
      'sdk': 36,
      'microphone_granted': false,
      'notifications_granted': false,
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          pendingCalls.add(call);
          if (call.method == 'device_status') return status;
          if (call.method == 'request_access_permission') {
            final args = Map<String, dynamic>.from(call.arguments as Map);
            final permission = args['permission'] as String;
            requested.add(permission);
            status['${permission}_granted'] = true;
            return {
              'permission': permission,
              'granted': true,
              'required': true,
            };
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('requests each optional permission only after its own tap', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AndroidAccessPanel())),
    );
    await tester.pumpAndSettle();

    expect(requested, isEmpty);
    expect(
      find.textContaining('always-listening microphone'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('request-microphone')), findsOneWidget);
    expect(find.byKey(const ValueKey('request-notifications')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('request-microphone')));
    await tester.pumpAndSettle();
    expect(requested, ['microphone']);

    await tester.tap(find.byKey(const ValueKey('request-notifications')));
    await tester.pumpAndSettle();
    expect(requested, ['microphone', 'notifications']);
    expect(
      pendingCalls.where((call) => call.method == 'request_access_permission'),
      hasLength(2),
    );
  });
}
