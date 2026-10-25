import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_assistant/assistant_state.dart';
import 'package:personal_assistant/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, dynamic> pickedFile;
  late List<http.Request> requests;
  late AssistantState state;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    pickedFile = {
      'name': 'lesson.pdf',
      'mime': 'application/pdf',
      'content_base64': base64Encode([1, 2, 3, 4]),
    };
    requests = [];
    state = AssistantState(
      clientFactory: () => MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'A useful answer.'},
                  ],
                },
                'groundingMetadata': {
                  'groundingChunks': [
                    {
                      'web': {
                        'uri': 'https://example.org/source',
                        'title': 'Example source',
                      },
                    },
                  ],
                  'groundingSupports': [
                    {
                      'segment': {'text': 'A supported claim.'},
                      'groundingChunkIndices': [0],
                    },
                  ],
                },
              },
            ],
          }),
          200,
        );
      }),
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      (_) async => 1,
    );
    messenger.setMockMethodCallHandler(AssistantState.device, (call) async {
      if (call.method == 'pick_file') return pickedFile;
      return null;
    });
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

  Future<void> pumpChat(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await state.local.load();
    await state.selectConversation('chat-feature-test', load: false);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: ChatScreen(state: state),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> cleanUp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    state.dispose();
  }

  void enableGemini() {
    state.chatMode = 'online';
    state.engine = 'gemini';
    state.geminiApiKey = 'test-api-key';
  }

  testWidgets(
    'web research asks permission, uses Google Search and saves citations',
    (tester) async {
      enableGemini();
      await pumpChat(tester);

      await tester.enterText(
        find.byType(TextField).last,
        'Latest battery research',
      );
      await tester.tap(find.text('Search web'));
      await tester.pump();
      await tester.tap(find.byTooltip('Send message'));
      await tester.pump();
      expect(find.text('Search the web with Gemini?'), findsOneWidget);
      expect(requests, isEmpty);

      await tester.tap(find.text('Send to Gemini'));
      await tester.pumpAndSettle();

      expect(requests, hasLength(1));
      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(body['tools'], [
        {'google_search': <String, dynamic>{}},
      ]);
      expect(find.text('WEB RESEARCH'), findsNWidgets(2));
      expect(find.textContaining('Example source'), findsOneWidget);
      expect(state.messages.last['sources'], hasLength(1));
      expect(
        state.local.chat(state.conversation).last['sources'],
        hasLength(1),
      );
      await cleanUp(tester);
    },
  );

  testWidgets(
    'unsupported offline mode sends nothing and preserves the research draft',
    (tester) async {
      await pumpChat(tester);
      await tester.enterText(
        find.byType(TextField).last,
        'Explain a new topic',
      );
      await tester.tap(find.text('Search web'));
      await tester.pump();
      await tester.tap(find.byTooltip('Send message'));
      await tester.pump();

      expect(requests, isEmpty);
      expect(state.messages, isEmpty);
      expect(
        find.textContaining('need Online chat with Gemini'),
        findsOneWidget,
      );
      expect(find.text('Explain a new topic'), findsOneWidget);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'file is reviewed, sent as inline Gemini data, and bytes are not saved',
    (tester) async {
      enableGemini();
      await pumpChat(tester);
      await tester.tap(find.text('Attach image or file'));
      await tester.pump();
      expect(find.text('lesson.pdf'), findsOneWidget);
      await tester.enterText(
        find.byType(TextField).last,
        'Summarize the lesson',
      );
      await tester.tap(find.byTooltip('Send message'));
      await tester.pump();
      expect(find.text('Send this file to Gemini?'), findsOneWidget);
      expect(requests, isEmpty);

      await tester.tap(find.text('Send to Gemini'));
      await tester.pumpAndSettle();

      expect(requests, hasLength(1));
      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      final parts = ((body['contents'] as List).single as Map)['parts'] as List;
      expect((parts.last as Map)['inline_data'], {
        'mime_type': 'application/pdf',
        'data': base64Encode([1, 2, 3, 4]),
      });
      expect(state.messages.first['attachmentName'], 'lesson.pdf');
      expect(
        state.local.chat(state.conversation).first['attachmentName'],
        'lesson.pdf',
      );
      expect(
        jsonEncode(state.local.chat(state.conversation)),
        isNot(contains(base64Encode([1, 2, 3, 4]))),
      );
      expect(find.textContaining('Attached: lesson.pdf'), findsOneWidget);
      await cleanUp(tester);
    },
  );

  testWidgets(
    'canceling file disclosure leaves attachment and question unsent',
    (tester) async {
      enableGemini();
      await pumpChat(tester);
      await tester.tap(find.text('Attach image or file'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).last, 'What is this?');
      await tester.tap(find.byTooltip('Send message'));
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(requests, isEmpty);
      expect(state.messages, isEmpty);
      expect(find.text('lesson.pdf'), findsOneWidget);
      expect(find.text('What is this?'), findsOneWidget);
      await cleanUp(tester);
    },
  );
}
