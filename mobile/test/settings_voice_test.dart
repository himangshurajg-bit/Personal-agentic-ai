import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:personal_assistant/assistant_state.dart';
import 'package:personal_assistant/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('settings group voice controls and describe safe limits', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AssistantState.device, (call) async {
          if (call.method == 'device_status') {
            return <String, dynamic>{
              'sdk': 36,
              'microphone_granted': false,
              'notifications_granted': false,
              'on_device_recognizer': false,
              'system_recognizer': false,
            };
          }
          return <String, dynamic>{};
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AssistantState.device, null);
    });

    final state = AssistantState();
    await state.initialize();
    await tester.pumpWidget(MaterialApp(home: Settings(state: state)));
    await tester.pumpAndSettle();

    expect(find.text('Voice & conversation'), findsOneWidget);
    await tester.tap(find.text('Voice & conversation'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('on-device-speech-rate')), findsOneWidget);
    expect(find.text('Read replies aloud'), findsOneWidget);
    expect(
      find.textContaining('not automatic language detection'),
      findsOneWidget,
    );
    expect(find.textContaining('does not listen continuously'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('AI, memory & models'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('AI, memory & models'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Privacy & access'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Privacy & access'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });
}
