import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    expect(find.byKey(const Key('voice-conversation-mode')), findsOneWidget);
    expect(find.text('Push-to-talk · one turn'), findsOneWidget);
    await tester.tap(find.byKey(const Key('voice-conversation-mode')));
    await tester.pumpAndSettle();
    expect(find.text('Hands-free · transcript review'), findsOneWidget);
    await tester.tap(find.text('Live Conversation · background mic').last);
    await tester.pumpAndSettle();
    expect(state.voiceConversationMode, 'live_conversation');
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
  testWidgets('voice picker previews only an installed offline voice', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    const tts = MethodChannel('flutter_tts');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(tts, (call) async {
          calls.add(call);
          if (call.method == 'getVoices') {
            return <Map<String, dynamic>>[
              {
                'name': 'Network voice',
                'locale': 'en-IN',
                'network_required': 1,
                'quality': 'very high',
              },
              {
                'name': 'Natural local voice',
                'locale': 'en-IN',
                'network_required': 0,
                'quality': 'very high',
                'latency': 'low',
              },
              {
                'name': 'Basic local voice',
                'locale': 'en-IN',
                'network_required': false,
                'quality': 'normal',
              },
            ];
          }
          return 1;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(tts, null);
    });
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
    await tester.tap(find.text('Voice & conversation'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('natural-voice-choice')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('natural-voice-choice')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Network voice'), findsNothing);
    expect(find.textContaining('Natural local voice'), findsOneWidget);
    await tester.tap(find.textContaining('Natural local voice'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('preview-natural-voice')));
    await tester.tap(find.byKey(const Key('preview-natural-voice')));
    await tester.pumpAndSettle();

    expect(calls.where((call) => call.method == 'setVoice').last.arguments, {
      'name': 'Natural local voice',
      'locale': 'en-IN',
    });
    expect(calls.where((call) => call.method == 'speak'), hasLength(1));
    expect(state.speechVoiceName, isNull); // Preview does not save preferences.
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets('Azure speech stays off until its disclosure is accepted', (
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
    expect(state.azureSpeechEnabled, isFalse);
    await tester.pumpWidget(MaterialApp(home: Settings(state: state)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voice & conversation'));
    await tester.pumpAndSettle();
    final toggle = find.byKey(const Key('azure-speech-opt-in'));
    await tester.scrollUntilVisible(
      toggle,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('Use Azure online speech?'), findsOneWidget);
    expect(
      find.textContaining('spoken assistant replies are sent'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(state.azureSpeechEnabled, isFalse);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enable Azure speech'));
    await tester.pumpAndSettle();
    expect(state.azureSpeechEnabled, isTrue);
    expect(
      find.textContaining('text is sent to Azure; English/Hindi only'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets('AI mode picker offers all five modes and saves selection', (
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
    await tester.scrollUntilVisible(
      find.text('AI, memory & models'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('AI, memory & models'));
    await tester.pumpAndSettle();

    final modePicker = find.byKey(const Key('ai-response-mode-setting'));
    expect(modePicker, findsOneWidget);
    await tester.tap(modePicker);
    await tester.pumpAndSettle();
    for (final label in const [
      'Professional',
      'Advanced',
      'Study',
      'Flurty',
      'Real Human',
    ]) {
      expect(find.text(label), findsWidgets);
    }
    await tester.tap(find.text('Flurty').last);
    await tester.pumpAndSettle();
    expect(state.aiMode, 'flurty');
    expect(await state.storage.read(key: 'ai_mode'), 'flurty');

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });
}
