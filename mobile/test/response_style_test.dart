import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_assistant/assistant_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('response style is locally saved, restored, and validated', () async {
    final first = AssistantState();
    await first.initialize();
    expect(first.responseStyle, 'balanced');

    await first.saveResponseStyle('concise');
    expect(await first.storage.read(key: 'response_style'), 'concise');
    await expectLater(
      first.saveResponseStyle('unsafe-custom-role'),
      throwsA(isA<ServiceException>()),
    );
    expect(first.responseStyle, 'concise');
    first.dispose();

    final restored = AssistantState();
    await restored.initialize();
    expect(restored.responseStyle, 'concise');
    restored.dispose();
  });

  test(
    'selected style reaches only the reviewed chat prompt and keeps guardrails',
    () async {
      Map<String, dynamic>? sentPrompt;
      final client = MockClient.streaming((request, body) async {
        final payload = jsonDecode(utf8.decode(await body.toBytes())) as Map;
        sentPrompt =
            jsonDecode(payload['text'] as String) as Map<String, dynamic>;
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(
              '{"type":"start"}\n{"type":"delta","text":"Short answer"}\n{"type":"done"}\\n',
            ),
          ),
          200,
        );
      });
      final state = AssistantState(clientFactory: () => client);
      await state.initialize();
      state.engine = 'private_service';
      state.privateServiceToken = 'test-only-token';
      await state.saveResponseStyle('concise');

      await state.send('Explain this briefly', approvedOnline: true);

      final instruction = sentPrompt!['instruction'] as String;
      expect(instruction, contains('Answer directly and briefly'));
      expect(instruction, contains('factual caution, safety boundaries'));
      expect(instruction, contains('approval requirements'));
      expect(sentPrompt!['user_message'], 'Explain this briefly');
      expect(state.messages.last['text'], 'Short answer');
      state.dispose();
      client.close();
    },
  );

  test('AI response modes persist and reject unsupported mode names', () async {
    final first = AssistantState();
    await first.initialize();
    expect(first.aiMode, 'professional');

    for (final mode in AssistantState.aiModeLabels.keys) {
      await first.saveAiMode(mode);
      expect(await first.storage.read(key: 'ai_mode'), mode);
    }
    await expectLater(
      first.saveAiMode('unreviewed-mode'),
      throwsA(isA<ServiceException>()),
    );
    expect(first.aiMode, 'real_human');
    first.dispose();

    final restored = AssistantState();
    await restored.initialize();
    expect(restored.aiMode, 'real_human');
    restored.dispose();
  });

  test(
    'each selected AI mode reaches the prompt with shared safety limits',
    () async {
      final instructions = <String>[];
      final client = MockClient.streaming((request, body) async {
        final payload = jsonDecode(utf8.decode(await body.toBytes())) as Map;
        final prompt =
            jsonDecode(payload['text'] as String) as Map<String, dynamic>;
        instructions.add(prompt['instruction'] as String);
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(
              '{"type":"start"}\\n{"type":"delta","text":"Reply"}\\n{"type":"done"}\\n',
            ),
          ),
          200,
        );
      });
      final state = AssistantState(clientFactory: () => client);
      await state.initialize();
      state.engine = 'private_service';
      state.privateServiceToken = 'test-only-token';

      for (final mode in AssistantState.aiModeLabels.keys) {
        await state.saveAiMode(mode);
        await state.send('prompt for $mode', approvedOnline: true);
        final instruction = instructions.last;
        expect(instruction, contains(AssistantState.aiModeInstructions[mode]!));
        expect(instruction, contains('AI mode affects response approach only'));
        expect(instruction, contains('grants no tools or action permissions'));
        expect(instruction, contains('never authorizes or performs an action'));
        expect(instruction, contains('cannot bypass confirmation or review'));
        expect(instruction, contains('never overrides user instructions'));
      }
      expect(
        instructions.toSet(),
        hasLength(AssistantState.aiModeLabels.length),
      );
      state.dispose();
      client.close();
    },
  );

  test('AI modes do not bypass online payload approval', () async {
    var requests = 0;
    final state = AssistantState(
      clientFactory: () {
        requests++;
        return MockClient((_) async => http.Response('', 500));
      },
    );
    await state.initialize();
    state.engine = 'private_service';

    for (final mode in AssistantState.aiModeLabels.keys) {
      await state.saveAiMode(mode);
      await state.send('must remain reviewed');
      expect(state.error, contains('Review and approve the online payload'));
      expect(state.messages, isEmpty);
    }
    expect(requests, 0);
    state.dispose();
  });
}
