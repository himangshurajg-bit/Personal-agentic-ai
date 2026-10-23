import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_assistant/assistant_state.dart';
import 'package:personal_assistant/engines.dart';
import 'package:personal_assistant/main.dart';
import 'package:personal_assistant/phone_screens.dart' show reviewOnline;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const device = AssistantState.device;

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'compatible connection probe validates model list without sending a prompt',
    () async {
      http.Request? captured;
      final state = AssistantState(
        clientFactory: () => MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 'study-model'},
              ],
            }),
            200,
          );
        }),
      );
      await state.saveSettings(
        'https://private.example',
        'private-token',
        'system',
        compatibleUrl: 'https://provider.example',
        compatibleSecret: 'key-not-for-logs',
      );
      await state.saveEngine('compatible', 'study-model', 'en-IN');

      final result = await state.testCompatibleApi();

      expect(captured?.method, 'GET');
      expect(captured?.url, Uri.parse('https://provider.example/v1/models'));
      expect(captured?.headers['Authorization'], 'Bearer key-not-for-logs');
      expect(captured?.body, isEmpty);
      expect(result, contains('Connected'));
      expect(result, contains('lists the configured model'));
      expect(result, isNot(contains('key-not-for-logs')));
      state.dispose();
    },
  );

  test(
    'compatible connection probe gives safe auth and endpoint diagnostics',
    () async {
      final state = AssistantState(
        clientFactory: () =>
            MockClient((_) async => http.Response('private error', 401)),
      );
      await state.saveSettings(
        'https://private.example',
        '',
        'system',
        compatibleUrl: 'https://provider.example',
        compatibleSecret: 'never-echo-this-key',
      );
      await state.saveEngine('compatible', 'study-model', 'en-IN');

      await expectLater(
        state.testCompatibleApi(),
        throwsA(
          isA<ServiceException>()
              .having((error) => error.message, 'message', contains('rejected'))
              .having(
                (error) => error.message,
                'message',
                isNot(contains('never-echo-this-key')),
              )
              .having(
                (error) => error.message,
                'message',
                isNot(contains('private error')),
              ),
        ),
      );
      state.dispose();
    },
  );

  test(
    'Gemini defaults to fixed 2.5 Flash and stores only the key locally',
    () async {
      final state = AssistantState();
      expect(state.engine, 'gemini');
      expect(AssistantState.geminiModel, 'gemini-2.5-flash');
      await state.saveGeminiApiKey('private-test-key');
      await state.saveEngine('gemini', '', 'en-IN');
      expect(state.model, 'gemini-2.5-flash');
      expect(
        await state.storage.read(key: 'gemini_api_key'),
        'private-test-key',
      );
      expect(state.config.origin, AssistantState.geminiEndpoint);
      expect(state.config.token, 'private-test-key');
      state.dispose();
    },
  );

  test('Gemini request uses fixed endpoint and auth header, never an alternate model', () async {
    final config = EngineConfig(
      mode: 'gemini',
      origin: AssistantState.geminiEndpoint,
      model: 'some-user-supplied-model',
      token: 'secret-key',
    );
    final request = config.request('personal', 'question');
    expect(request.method, 'POST');
    expect(
      request.url,
      Uri.parse('${AssistantState.geminiEndpoint}:generateContent'),
    );
    expect(request.url.queryParameters, isEmpty);
    expect(request.headers['x-goog-api-key'], 'secret-key');
    expect(request.headers.containsKey('Authorization'), isFalse);
    expect(jsonDecode(request.body), {
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': 'question'},
          ],
        },
      ],
    });
  });

  test(
    'Gemini JSON response produces one answer and completion event',
    () async {
      const config = EngineConfig(
        mode: 'gemini',
        origin: AssistantState.geminiEndpoint,
        model: AssistantState.geminiModel,
        token: 'secret-key',
      );
      final events = await config
          .events(
            Stream.value(
              utf8.encode(
                jsonEncode({
                  'candidates': [
                    {
                      'content': {
                        'parts': [
                          {'text': 'Hello'},
                        ],
                      },
                      'finishReason': 'STOP',
                    },
                  ],
                }),
              ),
            ),
          )
          .toList();
      expect(events, [
        {'type': 'delta', 'text': 'Hello'},
        {'type': 'done'},
      ]);
    },
  );

  test(
    'Gemini connection test runs one tiny fixed inference without chat data',
    () async {
      http.Request? captured;
      var requestCount = 0;
      final state = AssistantState(
        clientFactory: () => MockClient((request) async {
          requestCount++;
          captured = request;
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'OK'},
                    ],
                  },
                },
              ],
            }),
            200,
          );
        }),
      );
      await state.saveGeminiApiKey('not-for-logs');
      final result = await state.testGeminiApi();
      expect(requestCount, 1);
      expect(captured?.method, 'POST');
      expect(
        captured?.url,
        Uri.parse('${AssistantState.geminiEndpoint}:generateContent'),
      );
      expect(captured?.url.queryParameters, isEmpty);
      expect(captured?.headers['x-goog-api-key'], 'not-for-logs');
      expect(captured?.headers['Authorization'], isNull);
      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['contents'], [
        {
          'role': 'user',
          'parts': [
            {'text': 'Reply with exactly: OK'},
          ],
        },
      ]);
      expect(body['generationConfig'], {
        'maxOutputTokens': 8,
        'temperature': 0,
      });
      expect(result, contains('replied to the fixed connection test'));
      expect(result, contains('No chat content was sent'));
      expect(result, isNot(contains('not-for-logs')));
      expect(captured!.body, isNot(contains('personal')));
      state.dispose();
    },
  );

  test(
    'Gemini connection test reports auth and quota errors without key',
    () async {
      final state = AssistantState(
        clientFactory: () => MockClient(
          (_) async => http.Response('private provider error', 403),
        ),
      );
      await state.saveGeminiApiKey('never-echo-this-key');
      await expectLater(
        state.testGeminiApi(),
        throwsA(
          isA<ServiceException>()
              .having((error) => error.message, 'message', contains('rejected'))
              .having(
                (error) => error.message,
                'message',
                isNot(contains('never-echo-this-key')),
              )
              .having(
                (error) => error.message,
                'message',
                isNot(contains('private provider error')),
              ),
        ),
      );
      state.dispose();
    },
  );

  test(
    'Gemini connection test reports quota errors without exposing the key',
    () async {
      final state = AssistantState(
        clientFactory: () =>
            MockClient((_) async => http.Response('private error', 429)),
      );
      await state.saveGeminiApiKey('quota-test-key');
      await expectLater(
        state.testGeminiApi(),
        throwsA(
          isA<ServiceException>()
              .having(
                (error) => error.message,
                'message',
                contains('quota or rate limit'),
              )
              .having(
                (error) => error.message,
                'message',
                isNot(contains('quota-test-key')),
              )
              .having(
                (error) => error.message,
                'message',
                isNot(contains('private error')),
              ),
        ),
      );
      state.dispose();
    },
  );

  testWidgets(
    'general Settings routes API and MCP controls to their own screen',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            device,
            (call) async => <String, dynamic>{
              'sdk': 36,
              'microphone_granted': false,
              'notifications_granted': false,
              'on_device_recognizer': false,
              'system_recognizer': false,
            },
          );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(device, null);
      });

      final state = AssistantState()..engine = 'private_service';
      await tester.pumpWidget(
        MaterialApp(
          home: Settings(state: state),
          routes: {'/connections': (_) => ApiMcpSettings(state: state)},
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('API & MCP connections'),
        250,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('API & MCP connections'), findsOneWidget);
      expect(find.text('AI engine'), findsNothing);
      expect(find.text('Custom MCP servers'), findsNothing);

      await tester.tap(find.text('API & MCP connections'));
      await tester.pumpAndSettle();

      expect(find.byType(ApiMcpSettings), findsOneWidget);
      expect(find.text('AI engine'), findsOneWidget);
      expect(find.text('Private service origin'), findsOneWidget);
      expect(
        find.textContaining('127.0.0.1 and localhost point to the phone'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('Custom MCP servers'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Custom MCP servers'), findsOneWidget);
      expect(find.text('Add MCP server'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    },
  );

  testWidgets('Gemini setup requires one key and exposes a test action', (
    tester,
  ) async {
    final state = AssistantState();
    await tester.pumpWidget(MaterialApp(home: ApiMcpSettings(state: state)));
    await tester.pumpAndSettle();

    expect(find.text('Online · Gemini 2.5 Flash (default)'), findsOneWidget);
    expect(find.text('Gemini API key'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Test connection'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Test connection'), findsOneWidget);
    expect(
      find.textContaining('tiny fixed “Reply with exactly: OK” test'),
      findsOneWidget,
    );
    expect(find.text('API origin'), findsNothing);
    expect(find.text('Model ID'), findsNothing);
    expect(
      find.textContaining(
        'free-tier content may be used to improve its products',
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets('Gemini Test connection shows the provider result', (
    tester,
  ) async {
    http.Request? captured;
    final state = AssistantState(
      clientFactory: () => MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'OK'},
                  ],
                },
              },
            ],
          }),
          200,
        );
      }),
    );
    await tester.pumpWidget(MaterialApp(home: ApiMcpSettings(state: state)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'local-test-key');
    final testButton = find.text('Test connection');
    await tester.scrollUntilVisible(
      testButton,
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(testButton);
    await tester.pumpAndSettle();
    await tester.tap(testButton);
    await tester.pumpAndSettle();

    expect(captured?.method, 'POST');
    expect(
      captured?.url.path,
      contains('models/gemini-2.5-flash:generateContent'),
    );
    expect(
      find.textContaining('replied to the fixed connection test'),
      findsOneWidget,
    );
    expect(find.textContaining('local-test-key'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets('Gemini online-send review discloses free-tier data use', (
    tester,
  ) async {
    final state = AssistantState();
    bool? approved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                approved = await reviewOnline(
                  context,
                  state,
                  'A prompt that should remain local unless approved.',
                );
              },
              child: const Text('Review'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.text('Review online send'), findsOneWidget);
    expect(
      find.textContaining('may be used to improve its products'),
      findsOneWidget,
    );
    expect(
      find.text('A prompt that should remain local unless approved.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Keep local'));
    await tester.pumpAndSettle();
    expect(approved, false);
    state.dispose();
  });
}
