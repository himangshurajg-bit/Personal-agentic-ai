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
      expect(restored.searchChats('VELOCITY').single['conversation'], 'math');
      expect(restored.searchChats('synonym'), isEmpty);
      expect(restored.rows('tasks').single['done'], true);
      expect(restored.rows('attempts').single['answer'], '2 m/s');
      expect(jsonDecode(restored.export())['memories'], hasLength(1));
      await restored.deleteChat('math');
      expect(restored.rows('memories'), hasLength(1));
    },
  );
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
  test('offline AI blocked without any network fallback and online requires payload approval', () async {
    var calls = 0;
    final s = AssistantState(
      clientFactory: () => MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    await s.initialize();
    await s.send('hello');
    expect(s.error, contains('Offline AI is not installed'));
    expect(calls, 0);
    s.engine = 'compatible';
    await s.send('hello');
    expect(s.error, contains('Review and approve'));
    expect(calls, 0);
  });
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
    'action approval consumed before native call; unknown not replayed',
    () async {
      final s = AssistantState();
      await s.initialize();
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AssistantState.device, (call) async {
            calls++;
            expect(s.local.rows('actions').single['status'], 'unknown');
            throw PlatformException(code: 'lost');
          });
      final a = await s.prepareAction({
        'kind': 'open_app',
        'package': 'com.android.settings',
      });
      expect(calls, 0);
      final receipt = await s.executeApproved(a['id']);
      expect(receipt['result'], 'unknown');
      await expectLater(
        s.executeApproved(a['id']),
        throwsA(isA<ServiceException>()),
      );
      expect(calls, 1);
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
