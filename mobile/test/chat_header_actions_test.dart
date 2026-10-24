import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/assistant_state.dart';
import 'package:personal_assistant/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      (_) async => 1,
    );
    messenger.setMockMethodCallHandler(
      AssistantState.device,
      (_) async => true,
    );
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      null,
    );
    messenger.setMockMethodCallHandler(AssistantState.device, null);
  });

  testWidgets('busy chat uses typing dots instead of service waiting copy', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = AssistantState();
    await state.local.load();
    await state.selectConversation('typing-chat', load: false);
    state.busy = true;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: ChatScreen(state: state),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('typing-dot-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('typing-dot-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('typing-dot-2')), findsOneWidget);
    expect(find.text('Waiting for your service…'), findsNothing);

    state.partial = 'A partial reply';
    state.notifyListeners();
    await tester.pump();
    expect(find.text('A partial reply'), findsOneWidget);
    expect(find.byKey(const ValueKey('typing-dot-0')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    state.dispose();
  });

  testWidgets('chat header opens history and starts a fresh conversation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = AssistantState();
    await state.local.load();
    await state.local.writeChat('saved-chat', [
      {'role': 'user', 'text': 'A saved question', 'state': 'complete'},
    ]);
    await state.selectConversation('current-chat', load: false);
    await state.local.writeChat('current-chat', [
      {
        'role': 'user',
        'text': 'Current conversation text',
        'state': 'complete',
      },
    ]);
    await state.loadHistory();

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: ChatScreen(state: state),
        ),
      ),
    );
    await tester.pump();
    expect(find.byTooltip('Conversation history'), findsOneWidget);
    expect(find.byTooltip('New conversation'), findsOneWidget);

    await tester.tap(find.byTooltip('Conversation history'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Conversation history'), findsOneWidget);
    expect(find.text('A saved question'), findsOneWidget);

    await tester.tap(find.text('A saved question'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(state.conversation, 'saved-chat');
    expect(find.text('A saved question'), findsOneWidget);

    await tester.tap(find.byTooltip('New conversation'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(state.conversation, startsWith('chat_'));
    expect(state.messages, isEmpty);
    expect(find.text('A saved question'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    state.dispose();
  });
}
