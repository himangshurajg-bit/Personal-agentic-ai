import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:personal_assistant/engines.dart';
import 'package:personal_assistant/assistant_state.dart';
import 'package:personal_assistant/myra_task_routing.dart';

void main() {
  test(
    'Gemini and OpenAI use provider-specific HTTPS routes and model IDs',
    () {
      final openAi = const EngineConfig(
        mode: 'openai',
        origin: 'https://api.openai.com',
        model: 'gpt-4o-mini',
        token: 'openai-key',
      ).request('local', 'hello');
      expect(
        openAi.url.toString(),
        'https://api.openai.com/v1/chat/completions',
      );
      expect(openAi.headers['Authorization'], 'Bearer openai-key');
      expect(jsonDecode(openAi.body)['model'], 'gpt-4o-mini');

      final gemini = const EngineConfig(
        mode: 'gemini',
        origin: AssistantState.geminiEndpoint,
        model: AssistantState.geminiModel,
        token: 'gemini-key',
      ).request('local', 'hello');
      expect(
        gemini.url.toString(),
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent',
      );
      expect(gemini.headers['x-goog-api-key'], 'gemini-key');
      expect(
        jsonDecode(gemini.body)['contents'][0]['parts'][0]['text'],
        'hello',
      );
      final alternate = const EngineConfig(
        mode: 'gemini',
        origin: AssistantState.geminiModelsEndpoint,
        model: AssistantState.geminiFlashLiteModel,
        token: 'gemini-key',
      ).request('local', 'hello');
      expect(
        alternate.url.path,
        '/v1beta/models/gemini-2.5-flash-lite:generateContent',
      );
      for (final selectedModel in AssistantState.geminiModels) {
        final selected = EngineConfig(
          mode: 'gemini',
          origin: AssistantState.geminiModelsEndpoint,
          model: selectedModel,
          token: 'gemini-key',
        ).request('local', 'hello');
        expect(selected.url.path, endsWith('/$selectedModel:generateContent'));
      }
    },
  );

  test('Gemini exposes only reviewed task query routing when opted in', () {
    const geminiConfig = EngineConfig(
      mode: 'gemini',
      origin: AssistantState.geminiEndpoint,
      model: AssistantState.geminiModel,
      token: 'gemini-key',
    );
    final ordinary = jsonDecode(geminiConfig.request('local', 'hello').body);
    expect(ordinary.containsKey('tools'), isFalse);
    final enabled = jsonDecode(
      geminiConfig
          .request('local', 'show my tasks', enableMyraTaskListTool: true)
          .body,
    );
    expect(
      enabled['tools'][0]['functionDeclarations'][0]['name'],
      'read_myra_tasks',
    );
    expect(enabled['toolConfig']['functionCallingConfig']['mode'], 'AUTO');

    final openAi = const EngineConfig(
      mode: 'openai',
      origin: 'https://api.openai.com',
      model: 'gpt-4o-mini',
      token: 'key',
    ).request('local', 'hello', enableMyraTaskListTool: true);
    expect(jsonDecode(openAi.body).containsKey('tools'), isFalse);

    final toolReply = geminiConfig.myraTaskListResponseRequest(
      prompt: 'show my tasks',
      call: const MyraTaskFunctionCall(
        name: 'read_myra_tasks',
        args: {'state': 'all'},
      ),
      response: MyraTaskListPolicy.approvedResponse('1. [open] Example'),
    );
    final body = jsonDecode(toolReply.body);
    expect(body['contents'], hasLength(3));
    expect(body['contents'][1]['role'], 'model');
    expect(
      body['contents'][2]['parts'][0]['functionResponse']['response']['result'],
      contains('1. [open] Example'),
    );
    expect(toolReply.headers['x-goog-api-key'], 'gemini-key');
  });

  test(
    'Gemini parser recognizes one function call and rejects ambiguous calls',
    () async {
      const gemini = EngineConfig(
        mode: 'gemini',
        origin: AssistantState.geminiEndpoint,
        model: AssistantState.geminiModel,
        token: 'key',
      );
      final call = await gemini
          .events(
            Stream.value(
              utf8.encode(
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
              ),
            ),
          )
          .toList();
      expect(call.first['type'], 'function_call');
      expect(call.first['name'], 'read_myra_tasks');
      expect(call.last['type'], 'done');

      await expectLater(
        gemini
            .events(
              Stream.value(
                utf8.encode(
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
                ),
              ),
            )
            .toList(),
        throwsA(isA<ServiceException>()),
      );
    },
  );

  test(
    'cloud provider adapters fail closed on missing keys or unsafe origins',
    () {
      expect(
        () => const EngineConfig(
          mode: 'openai',
          origin: 'https://api.openai.com',
          model: 'gpt-4o-mini',
          token: '',
        ).request('local', 'hello'),
        throwsA(isA<ServiceException>()),
      );
      expect(
        () => const EngineConfig(
          mode: 'gemini',
          origin: 'http://generativelanguage.googleapis.com',
          model: AssistantState.geminiModel,
          token: 'key',
        ).request('local', 'hello'),
        throwsA(isA<ServiceException>()),
      );
      expect(
        () => const EngineConfig(
          mode: 'gemini',
          origin: AssistantState.geminiModelsEndpoint,
          model: 'unlisted-paid-model',
          token: 'key',
        ).request('local', 'hello'),
        throwsA(isA<ServiceException>()),
      );
    },
  );
}
