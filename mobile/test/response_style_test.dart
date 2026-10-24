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
}
