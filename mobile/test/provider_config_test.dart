import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:personal_assistant/engines.dart';
import 'package:personal_assistant/assistant_state.dart';

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
