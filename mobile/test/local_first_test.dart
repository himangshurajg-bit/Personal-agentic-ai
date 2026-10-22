import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_assistant/assistant_state.dart';
import 'package:personal_assistant/engines.dart';
import 'package:personal_assistant/phone_data.dart';
import 'package:personal_assistant/main.dart';
import 'package:personal_assistant/phone_screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'local persistence/search/tasks/attempts/export reload without network',
    () async {
      const secure = FlutterSecureStorage();
      final data = PhoneData(secure);
      await data.load();
      await data.writeChat('math', [
        {'role': 'user', 'text': 'explain velocity'},
      ]);
      await data.saveMemory('short answers', 'math');
      await data.task('Review vectors');
      await data.setTask(data.rows('tasks').single['id'], true);
      await data.attempt({
        'topic': 'motion',
        'answer': '2 m/s',
        'result': 'not checked',
      });
      final restored = PhoneData(secure);
      await restored.load();
      expect(
        (await restored.searchChats('VELOCITY')).single['conversation'],
        'math',
      );
      expect(await restored.searchChats('synonym'), isEmpty);
      expect(restored.lastSearchUsedRust, isFalse);
      expect(restored.rows('tasks').single['done'], true);
      expect(restored.rows('attempts').single['answer'], '2 m/s');
      expect(jsonDecode(restored.export())['memories'], hasLength(1));
      await restored.deleteChat('math');
      expect(restored.rows('memories'), hasLength(1));
    },
  );
  test(
    'flashcards migrate old local records and schedule only actual reviews',
    () async {
      const secure = FlutterSecureStorage();
      await secure.write(
        key: 'phone_data_v1',
        value: jsonEncode({
          'chats': {
            'older': [
              {'role': 'user', 'text': 'keep me'},
            ],
          },
          'memories': [],
          'tasks': [],
          'attempts': [],
          'actions': [],
        }),
      );
      final data = PhoneData(secure);
      await data.load();
      expect(data.chat('older').single['text'], 'keep me');
      expect(data.studyDecks, isEmpty);
      expect(data.rows('flashcards'), isEmpty);

      final deck = await data.createStudyDeck('  Algebra  ');
      final card = await data.createFlashcard(deck, '  2 + 2? ', '  4  ');
      expect(data.studyDecks.single['title'], 'Algebra');
      expect(data.dueFlashcards().single['id'], card);
      expect(data.rows('study_reviews'), isEmpty);
      final t = DateTime.fromMillisecondsSinceEpoch(
        data.rows('flashcards').single['due_at'],
        isUtc: true,
      ).add(const Duration(seconds: 1));
      await data.reviewFlashcard(card, 'good', reviewedAt: t);
      final first = data.rows('flashcards').single;
      expect(first['review_count'], 1);
      expect(first['repetitions'], 1);
      expect(
        first['due_at'],
        t.add(const Duration(days: 1)).millisecondsSinceEpoch,
      );
      expect(
        data.dueFlashcards(now: t.add(const Duration(hours: 23))),
        isEmpty,
      );
      expect(
        data.dueFlashcards(now: t.add(const Duration(days: 1))),
        hasLength(1),
      );

      final next = DateTime.fromMillisecondsSinceEpoch(
        first['due_at'],
        isUtc: true,
      );
      await data.reviewFlashcard(card, 'again', reviewedAt: next);
      final second = data.rows('flashcards').single;
      expect(second['review_count'], 2); // both real reviews remain counted
      expect(second['repetitions'], 0); // Again restarts the scheduling streak
      expect(
        second['due_at'],
        next.add(const Duration(minutes: 10)).millisecondsSinceEpoch,
      );
      expect(data.rows('study_reviews'), hasLength(2));
      expect(
        data.dueFlashcards(now: next.add(const Duration(minutes: 9))),
        isEmpty,
      );
      expect(
        data.dueFlashcards(now: next.add(const Duration(minutes: 10))),
        hasLength(1),
      );

      await data.updateFlashcard(card, 'Updated front', 'Updated back');
      await data.updateStudyDeck(deck, 'Updated deck');
      final restored = PhoneData(secure);
      await restored.load();
      expect(restored.studyDecks.single['title'], 'Updated deck');
      expect(restored.rows('flashcards').single['front'], 'Updated front');
      expect(jsonDecode(restored.export())['study_reviews'], hasLength(2));
      await restored.deleteFlashcard(card);
      expect(restored.rows('flashcards'), isEmpty);
      await restored.deleteStudyDeck(deck);
      expect(restored.studyDecks, isEmpty);
      expect(restored.rows('study_reviews'), hasLength(2));
      expect(restored.chat('older').single['text'], 'keep me');
    },
  );

  testWidgets('flashcard flow creates and reviews a user-authored card', (
    tester,
  ) async {
    const secure = FlutterSecureStorage();
    final data = PhoneData(secure);
    await data.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: LocalFlashcards(data: data)),
        ),
      ),
    );

    await tester.tap(find.text('New deck'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Biology');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Biology'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add card'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'What is a cell?');
    await tester.enterText(
      find.byType(TextField).at(1),
      'The basic unit of life.',
    );
    await tester.tap(find.text('Save card'));
    await tester.pumpAndSettle();
    expect(find.text('What is a cell?'), findsOneWidget);

    await tester.tap(find.text('Review due cards'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show answer'));
    await tester.pumpAndSettle();
    expect(find.text('The basic unit of life.'), findsOneWidget);
    await tester.tap(find.text('Good'));
    await tester.pumpAndSettle();
    expect(data.rows('study_reviews'), hasLength(1));
    expect(
      find.textContaining('1 reviewed today · 1 total reviews'),
      findsOneWidget,
    );
  });

  test('memory scope applies and only relevant approved facts selected; no implicit capture', () async {
    final s = AssistantState();
    await s.initialize();
    await s.remember('blue is my color', scope: 'all');
    await s.remember('physics project', scope: 'other');
    expect(s.local.relevant('blue color', 'personal'), hasLength(1));
    expect(s.local.relevant('physics', 'personal'), isEmpty);
    await s.local.writeChat('personal', [
      {'role': 'user', 'text': 'secret automatic preference'},
    ]);
    expect(s.local.rows('memories'), hasLength(2));
    final id = s.memories.first['id'];
    await s.forget(id);
    expect(s.local.relevant('blue', 'personal'), isEmpty);
  });
  test(
    'offline chat stays opt-in and never falls back to the network',
    () async {
      var calls = 0;
      final s = AssistantState(
        clientFactory: () => MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );
      await s.initialize();
      for (final locale in AssistantState.languageLabels.keys) {
        await s.saveEngine('offline', '', locale);
        await s.send('Explain Newton’s second law with a worked example.');
        expect(
          s.error,
          contains('Experimental Gemma chat is off'),
          reason:
              'locale $locale remains behind the offline qualification gate',
        );
        expect(
          calls,
          0,
          reason: 'locale $locale must not trigger network fallback',
        );
      }
      await s.saveEngine('compatible', 'test-model', 'en-IN');
      await s.send('hello');
      expect(s.error, contains('Review and approve'));
      expect(calls, 0);
      s.dispose();
    },
  );

  test(
    'opted-in offline chat routes only through the local native runtime',
    () async {
      final calls = <MethodCall>[];
      var networkCalls = 0;
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(AssistantState.offlineModel, null),
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AssistantState.offlineModel, (call) async {
            calls.add(call);
            if (call.method == 'run_chat') return 'A local answer.';
            return true;
          });
      final s = AssistantState(
        clientFactory: () => MockClient((_) async {
          networkCalls++;
          return http.Response('{}', 200);
        }),
      );
      await s.initialize();
      expect(s.experimentalOfflineChatEnabled, isFalse);
      await s.saveExperimentalOfflineChat(true);
      await s.send('Explain Newton’s second law.');

      expect(networkCalls, 0);
      expect(
        calls.map((call) => call.method),
        contains('set_experimental_chat_enabled'),
      );
      final chatCall = calls.singleWhere((call) => call.method == 'run_chat');
      expect((chatCall.arguments as Map)['experimental_opt_in'], isTrue);
      final prompt = jsonDecode(
        (chatCall.arguments as Map)['prompt'] as String,
      );
      expect(prompt['user_message'], 'Explain Newton’s second law.');
      expect(s.messages.last, {
        'role': 'assistant',
        'text': 'A local answer.',
        'state': 'complete',
        'engine': 'offline',
      });
      expect(s.error, isEmpty);

      final restored = AssistantState();
      await restored.initialize();
      expect(restored.experimentalOfflineChatEnabled, isTrue);
      s.dispose();
      restored.dispose();
    },
  );

  for (final entry in const {
    'en-IN': 'English',
    'as-IN': 'Assamese (অসমীয়া)',
    'hi-IN': 'Hindi in Devanagari script',
    'hi-Latn-IN': 'natural Hinglish, mixing Hindi and English in Latin script',
  }.entries) {
    test('online tutor request names ${entry.value}', () async {
      http.Request? sent;
      final s = AssistantState(
        clientFactory: () => MockClient((request) async {
          sent = request;
          return http.Response(
            'data: {"choices":[{"delta":{"content":"Test"},"finish_reason":null}]}\n\n'
            'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\n'
            'data: [DONE]\n\n',
            200,
          );
        }),
      );
      await s.initialize();
      await s.saveEngine('compatible', 'test-model', entry.key);
      s.compatibleApiEndpoint = 'https://provider.example';
      s.compatibleApiKey = 'test-only-key';
      await s.send(
        'Explain Newton’s second law with a worked example.',
        approvedOnline: true,
      );
      final body = jsonDecode(sent!.body) as Map<String, dynamic>;
      final messages = body['messages'] as List;
      final prompt = jsonDecode(
        messages.single['content'] as String,
      ) as Map<String, dynamic>;
      expect(prompt['instruction'], contains(entry.value));
      expect(s.error, isEmpty);
      s.dispose();
    });
  }
  test('compatible SSE handles chunk boundaries, errors and completion', () async {
    const c = EngineConfig(
      mode: 'compatible',
      origin: 'https://provider.example',
      model: 'chosen',
      token: 'test',
    );
    final input =
        'data: {"choices":[{"delta":{"content":"নমস্কাৰ"},"finish_reason":null}]}\n\ndata: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\ndata: [DONE]\n\n';
    final events = await c
        .events(Stream.fromIterable(utf8.encode(input).map((x) => [x])))
        .toList();
    expect(events.first['text'], 'নমস্কাৰ');
    expect(events.last['type'], 'done');
    await expectLater(
      c
          .events(
            Stream.value(utf8.encode('data: {"error":{"message":"bad"}}\n')),
          )
          .toList(),
      throwsA(isA<ServiceException>()),
    );
    expect(
      () => const EngineConfig(
        mode: 'compatible',
        origin: 'http://127.0.0.1',
        model: 'x',
        token: 'test',
      ).request('id', 'hello'),
      throwsA(isA<ServiceException>()),
    );
  });
  test(
    'online approved payload does not silently include local private data',
    () async {
      String? body;
      final s = AssistantState(
        clientFactory: () => MockClient.streaming((r, b) async {
          body = utf8.decode(await b.toBytes());
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(
                'data: {"choices":[{"delta":{"content":"Hi"}}]}\n\ndata: [DONE]\n\n',
              ),
            ),
            200,
          );
        }),
      );
      await s.initialize();
      s.engine = 'compatible';
      s.endpoint = 'https://provider.example';
      s.token = 'test';
      s.model = 'selected';
      await s.saveNote('private notebook');
      await s.remember('hidden memory');
      await s.send('hello', approvedOnline: true);
      expect(body, contains('hello'));
      expect(body, isNot(contains('private notebook')));
      expect(body, isNot(contains('hidden memory')));
      expect(s.messages.last['text'], 'Hi');
    },
  );
  test(
    'app launches need a current picker selection and one-use owner approval',
    () async {
      final s = AssistantState();
      await s.initialize();
      var executeCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AssistantState.device, (call) async {
            if (call.method == 'list_launchable_apps') {
              return [
                {
                  'package': 'com.example.reader',
                  'label': 'Reader',
                  'icon_png_base64': null,
                },
              ];
            }
            if (call.method == 'execute') {
              executeCalls++;
              expect(s.local.rows('actions').single['status'], 'unknown');
              throw PlatformException(code: 'lost');
            }
            fail('Unexpected device method: ${call.method}');
          });
      final apps = await s.loadLaunchableApps();
      expect(apps.map((app) => app.label), ['Reader']);
      await expectLater(
        s.prepareAction({
          'kind': 'open_app',
          'package': 'com.example.reader',
          'app_name': 'Reader',
        }),
        throwsA(isA<ServiceException>()),
      );
      await expectLater(
        s.prepareAction({
          'kind': 'open_app',
          'package': 'com.example.arbitrary',
          'app_name': 'Made up',
        }),
        throwsA(isA<ServiceException>()),
      );
      final draft = await s.prepareSelectedAppLaunch(apps.single);
      expect(draft['status'], 'prepared');
      expect(executeCalls, 0);
      final receipt = await s.executeApproved(draft['id']);
      expect(receipt['result'], 'unknown');
      await expectLater(
        s.executeApproved(draft['id']),
        throwsA(isA<ServiceException>()),
      );
      expect(executeCalls, 1);
      expect(
        () => s.validateAction({'kind': 'shell', 'command': 'anything'}),
        throwsA(isA<ServiceException>()),
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AssistantState.device, null);
    },
  );
  test('assistant name validates/persists as data and voice mode independent of inference', () async {
    final s = AssistantState();
    await s.initialize();
    await s.setAssistantName('হিৰাকী');
    await s.saveSpeechMode('online');
    final r = AssistantState();
    await r.initialize();
    expect(r.assistantName, 'হিৰাকী');
    expect(r.speechMode, 'online');
    expect(r.engine, 'offline');
    await expectLater(s.setAssistantName(''), throwsA(isA<ServiceException>()));
    await expectLater(
      s.saveSpeechMode('silent fallback'),
      throwsA(isA<ServiceException>()),
    );
  });
  for (final code in ['denied', 'unavailable', 'no_network']) {
    testWidgets('speech $code is explicit and never changes mode or calls AI', (
      tester,
    ) async {
      final calls = <Map>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        AssistantState.device,
        (c) async {
          if (c.method == 'voice_start') {
            calls.add(Map.from(c.arguments));
            throw PlatformException(
              code: code,
              message: 'Speech $code; type instead',
            );
          }
          return true;
        },
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('flutter_tts'),
        (_) async => 1,
      );
      final s = AssistantState()
        ..ready = true
        ..appLockConfigurationReady = true
        ..onboarded = true;
      await tester.pumpWidget(AssistantApp(state: s));
      await tester.tap(find.text('Chat').last);
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await tester.tap(find.byTooltip('Use microphone'));
      await tester.pumpAndSettle();
      expect(calls.single['mode'], 'offline');
      expect(calls.single['approved_online'], false);
      expect(s.engine, 'offline');
      expect(find.textContaining('Speech $code'), findsOneWidget);
      expect(find.text('Microphone on • listening'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      s.dispose();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        AssistantState.device,
        null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('flutter_tts'),
        null,
      );
    });
  }
  testWidgets(
    'online microphone sends nothing before deliberate audio disclosure approval',
    (tester) async {
      var starts = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        AssistantState.device,
        (c) async {
          if (c.method == 'voice_start') {
            starts++;
            expect(c.arguments['approved_online'], true);
            expect(c.arguments['mode'], 'online');
          }
          return true;
        },
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('flutter_tts'),
        (_) async => 1,
      );
      final s = AssistantState()
        ..ready = true
        ..appLockConfigurationReady = true
        ..onboarded = true
        ..speechMode = 'online';
      await tester.pumpWidget(AssistantApp(state: s));
      await tester.tap(find.text('Chat').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Use microphone'));
      await tester.pumpAndSettle();
      expect(starts, 0);
      expect(find.text('Use online speech recognition?'), findsOneWidget);
      await tester.tap(find.text('Start online microphone'));
      await tester.pumpAndSettle();
      expect(starts, 1);
      await tester.pumpWidget(const SizedBox());
      s.dispose();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        AssistantState.device,
        null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('flutter_tts'),
        null,
      );
    },
  );
}
