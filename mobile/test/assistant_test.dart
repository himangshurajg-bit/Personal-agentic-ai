import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_assistant/assistant_state.dart';
import 'package:personal_assistant/main.dart';

AssistantState stateWith(http.Client client) =>
    AssistantState(clientFactory: () => client)
      ..token = 'test-only-token-not-a-live-secret'
      ..engine = 'private_service';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  // Optional readable widget captures; normal tests retain Flutter's default test font.
  setUpAll(() async {
    if (Platform.environment['CAPTURE_REAL_FONTS'] == '1') {
      final root = Platform.environment['FLUTTER_ROOT']!;
      final loader = FontLoader('Roboto')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              await File(
                '$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
              ).readAsBytes(),
            ),
          ),
        );
      await loader.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              await File(
                '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
              ).readAsBytes(),
            ),
          ),
        );
      await icons.load();
    }
  });
  test(
    'conversation selection persists, reloads history and clears stale reply',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final state = stateWith(
        MockClient((req) async {
          expect(req.url.path, '/conversations/older');
          return http.Response(
            jsonEncode([
              {'role': 'user', 'text': 'old chat', 'complete': true},
            ]),
            200,
          );
        }),
      );
      await state.local.writeChat('older', [
        {'role': 'user', 'text': 'old chat', 'state': 'complete'},
      ]);
      state.messages = [
        {'role': 'user', 'text': 'stale'},
      ];
      state.lastPrompt = 'stale';
      state.error = 'stale';
      await state.selectConversation('older');
      expect(state.conversation, 'older');
      expect(state.messages.single['text'], 'old chat');
      expect(await state.storage.read(key: 'conversation'), 'older');
      await state.selectConversation('new-chat', load: false);
      expect(state.messages, isEmpty);
      expect(state.lastPrompt, isEmpty);
      expect(state.error, isEmpty);
      await expectLater(
        state.selectConversation('../bad'),
        throwsA(isA<ServiceException>()),
      );
      expect(state.conversation, 'new-chat');
    },
  );
  test(
    'endpoint enforces TLS or explicit loopback and refuses credentials',
    () {
      for (final value in [
        'http://127.0.0.1:8766',
        'http://10.0.2.2:8766',
        'https://private.example',
      ]) {
        expect(checkedEndpoint(value).hasAuthority, true);
      }
      for (final value in [
        'http://public.example',
        'https://user:pass@private.example',
        'file:///tmp/x',
        'https://x.test/path',
        'https://x.test?token=secret',
      ]) {
        expect(() => checkedEndpoint(value), throwsA(isA<ServiceException>()));
      }
    },
  );
  test(
    'stream renders completed Unicode reply, token and exact conversation',
    () async {
      final state = stateWith(
        MockClient.streaming((req, body) async {
          expect(req.headers['Authorization'], startsWith('Bearer '));
          expect(
            jsonDecode(utf8.decode(await body.toBytes()))['conversation'],
            'personal',
          );
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(
                '{"type":"start"}\n{"type":"delta","text":"नमस्ते "}\n{"type":"delta","text":"world"}\n{"type":"done"}\n',
              ),
            ),
            200,
          );
        }),
      );
      await state.send('hello', approvedOnline: true);
      expect(state.messages.last['text'], 'नमस्ते world');
      expect(state.messages.last['state'], 'complete');
      expect(state.error, isEmpty);
      expect(state.busy, false);
      state.dispose();
    },
  );
  test(
    'broken response preserves partial as interrupted, no automatic retry',
    () async {
      var calls = 0;
      final state = stateWith(
        MockClient.streaming((req, body) async {
          calls++;
          return http.StreamedResponse(
            Stream.value(utf8.encode('{"type":"delta","text":"partial"}\n')),
            200,
          );
        }),
      );
      await state.send('hi', approvedOnline: true);
      expect(calls, 1);
      expect(state.messages.last['state'], 'interrupted');
      expect(state.error, contains('before completion'));
      state.dispose();
    },
  );
  test('rate limited and missing provider are clear failures without invented replies', () async {
    for (final status in [429, 503, 401]) {
      var calls = 0;
      final state = stateWith(
        MockClient((_) async {
          calls++;
          return http.Response('{}', status);
        }),
      );
      await state.send('hi', approvedOnline: true);
      expect(state.messages.where((m) => m['role'] == 'assistant'), isEmpty);
      expect(state.error, AssistantState.describeStatus(status));
      expect(calls, 1);
      state.dispose();
    }
  });
  test(
    'timeout fails once; settings/unconfigured notebook stays available',
    () async {
      var calls = 0;
      final state = stateWith(
        MockClient((_) async {
          calls++;
          throw TimeoutException('weak network');
        }),
      );
      await state.send('hi', approvedOnline: true);
      expect(state.error, contains('timed out'));
      expect(calls, 1);
      state.token = '';
      await state.send('again', approvedOnline: true);
      expect(state.error, contains('Configure this provider'));
      state.dispose();
    },
  );
  test('approved local memory save/edit/delete never calls a server', () async {
    var calls = 0;
    final state = stateWith(
      MockClient((_) async {
        calls++;
        throw StateError('unexpected network');
      }),
    );
    state.conversation = 'study';
    await state.remember('I prefer short answers');
    expect(state.memories.single['conversation'], 'study');
    final id = state.memories.single['id'];
    await state.editMemory(
      id,
      'I prefer short explanations',
      type: 'project',
      scope: 'all',
    );
    expect(state.memories.single['type'], 'project');
    await state.forget(id);
    expect(state.memories, isEmpty);
    expect(calls, 0);
  });
  test(
    'history selection persists the scope and reloads its messages',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final state = stateWith(
        MockClient((req) async {
          expect(req.url.path, '/conversations/earlier');
          return http.Response(
            '[{"role":"user","text":"old question","state":"complete"}]',
            200,
          );
        }),
      );
      await state.local.writeChat('earlier', [
        {'role': 'user', 'text': 'old question', 'state': 'complete'},
      ]);
      await state.selectConversation('earlier');
      expect(state.conversation, 'earlier');
      expect(state.messages.single['text'], 'old question');
      expect(await state.storage.read(key: 'conversation'), 'earlier');
      await state.selectConversation('new_chat', load: false);
      expect(state.messages, isEmpty);
      expect(state.lastPrompt, isEmpty);
      state.dispose();
    },
  );
  test('stop marks partial interrupted and never pretends completion', () {
    final state = AssistantState()
      ..busy = true
      ..partial = 'not done';
    state.stop();
    expect(state.busy, false);
    expect(state.messages.last['state'], 'interrupted');
    state.dispose();
  });
  testWidgets(
    'onboarding at phone width is readable and offers no early mic permission',
    (tester) async {
      tester.view.physicalSize = const Size(382, 754);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = AssistantState()..ready = true;
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('capture'),
          child: AssistantApp(state: state),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Onboarding), findsOneWidget);
      if (Platform.environment['CAPTURE_REAL_FONTS'] == '1') {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File('/tmp/personal-ai-onboarding-widget.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    },
  );
  testWidgets('home phone layout and dark theme render without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(382, 754);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = AssistantState()
      ..ready = true
      ..onboarded = true
      ..theme = 'dark';
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('capture'),
        child: AssistantApp(state: state),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Home), findsOneWidget);
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('/tmp/personal-ai-home-widget.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });
  testWidgets(
    'microphone denial remains typed-chat usable; no early microphone call',
    (tester) async {
      const mic = AssistantState.device;
      const tts = MethodChannel('flutter_tts');
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(mic, (
        call,
      ) async {
        calls.add(call.method);
        if (call.method == 'voice_start') {
          throw PlatformException(
            code: 'denied',
            message: 'Microphone permission denied. Typing still works.',
          );
        }
        return true;
      });
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        tts,
        (call) async => 1,
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          mic,
          null,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          tts,
          null,
        );
      });
      final state = stateWith(MockClient((_) async => http.Response('[]', 200)))
        ..ready = true
        ..onboarded = true;
      await tester.pumpWidget(AssistantApp(state: state));
      await tester.tap(find.text('Chat').last);
      await tester.pumpAndSettle();
      expect(calls.where((x) => x == 'voice_start'), isEmpty);
      await tester.tap(find.byTooltip('Use microphone'));
      await tester.pumpAndSettle();
      expect(calls.where((x) => x == 'voice_start').length, 1);
      expect(
        find.textContaining('Microphone permission denied'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Microphone on • listening'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    },
  );
  testWidgets(
    'denied device action is reviewed, attempted once, and reported denied not scheduled',
    (tester) async {
      var nativeCalls = 0;
      final paths = <String>[];
      String? reportedResult;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        AssistantState.device,
        (call) async {
          nativeCalls++;
          return {
            'result': 'denied',
            'detail':
                'Notification permission denied; no reminder was scheduled.',
          };
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          AssistantState.device,
          null,
        ),
      );
      final state =
          stateWith(
              MockClient((req) async {
                paths.add(req.url.path);
                if (req.url.path.endsWith('/prepare')) {
                  return http.Response(
                    jsonEncode({'id': 'one', 'approval_token': 'a' * 32}),
                    200,
                  );
                }
                if (req.url.path.endsWith('/approve')) {
                  return http.Response(
                    jsonEncode({
                      'action': {
                        'kind': 'reminder',
                        'title': 'Study',
                        'at_ms': DateTime.now()
                            .add(const Duration(hours: 1))
                            .millisecondsSinceEpoch,
                      },
                    }),
                    200,
                  );
                }
                reportedResult = jsonDecode(req.body)['result'] as String;
                return http.Response('{}', 200);
              }),
            )
            ..ready = true
            ..onboarded = true;
      await tester.pumpWidget(AssistantApp(state: state));
      final home = tester.widget<Home>(find.byType(Home));
      final future = home.action(tester.element(find.byType(Home)), {
        'kind': 'reminder',
        'title': 'Study',
        'at_ms': DateTime.now()
            .add(const Duration(hours: 1))
            .millisecondsSinceEpoch,
      });
      await tester.pumpAndSettle();
      expect(nativeCalls, 0);
      await tester.tap(find.text('Approve this action'));
      await tester.pump();
      await future;
      await tester.pump(const Duration(milliseconds: 300));
      expect(nativeCalls, 1);
      expect(reportedResult, isNull);
      expect(state.local.rows('actions').single['status'], 'denied');
      expect(paths, isEmpty);
      expect(
        find.text('Notification permission denied; no reminder was scheduled.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    },
  );
}
