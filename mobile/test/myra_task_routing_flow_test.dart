import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_assistant/assistant_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'sends task excerpt only after direct request and review approval',
    () async {
      final requestBodies = <Map<String, dynamic>>[];
      final state = AssistantState(
        clientFactory: () => MockClient((request) async {
          requestBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          if (requestBodies.length == 1) {
            return http.Response(
              jsonEncode({
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {
                          'functionCall': {
                            'name': 'read_myra_tasks',
                            'args': {'state': 'open'},
                          },
                        },
                      ],
                    },
                  },
                ],
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'You have one open task.'},
                    ],
                  },
                },
              ],
            }),
            200,
          );
        }),
      );
      await state.initialize();
      await state.saveChatMode('online');
      state.engine = 'gemini';
      state.geminiApiKey = 'test-only-key';
      state.geminiModelSelection = AssistantState.geminiModel;

      var reviews = 0;
      await state.send(
        'List my open tasks',
        reviewMyraTaskList: (request) async {
          reviews++;
          expect(request.state, 'open');
          return '[open] Study vectors';
        },
      );

      expect(reviews, 1);
      expect(requestBodies, hasLength(2));
      expect(requestBodies.first['tools'], isNotNull);
      expect(jsonEncode(requestBodies.first), isNot(contains('Study vectors')));
      final contents = requestBodies.last['contents'] as List;
      final functionResult =
          (((contents[2] as Map)['parts'] as List).single
                  as Map)['functionResponse']
              as Map;
      expect(
        functionResult['response']['result'],
        contains('[open] Study vectors'),
      );
      expect(state.messages.last['text'], 'You have one open task.');
      expect(state.error, isEmpty);
      state.dispose();
    },
  );

  test(
    'refuses model-requested task access without a direct latest-message ask',
    () async {
      var networkCalls = 0;
      var reviews = 0;
      final state = AssistantState(
        clientFactory: () => MockClient((request) async {
          networkCalls++;
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {
                        'functionCall': {
                          'name': 'read_myra_tasks',
                          'args': {'state': 'all'},
                        },
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
      await state.initialize();
      await state.saveChatMode('online');
      state.engine = 'gemini';
      state.geminiApiKey = 'test-only-key';
      state.geminiModelSelection = AssistantState.geminiModel;

      await state.send(
        'Tell me about tasks in general',
        reviewMyraTaskList: (_) async {
          reviews++;
          return '[open] Study vectors';
        },
      );

      expect(networkCalls, 1);
      expect(reviews, 0);
      expect(state.error, contains('did not directly ask'));
      expect(
        state.messages.where((message) => message['role'] == 'assistant'),
        isEmpty,
      );
      state.dispose();
    },
  );
}
