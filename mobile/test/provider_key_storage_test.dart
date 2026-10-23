import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:personal_assistant/assistant_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'OpenAI, Gemini and Deepgram keys use distinct secure-storage slots',
    () async {
      final state = AssistantState();
      await state.initialize();
      await state.saveCloudProviderKey('openai', 'openai-secret');
      await state.saveCloudProviderKey('gemini', 'gemini-secret');
      await state.saveCloudProviderKey('deepgram', 'deepgram-secret');
      expect(await state.storage.read(key: 'openai_api_key'), 'openai-secret');
      expect(await state.storage.read(key: 'gemini_api_key'), 'gemini-secret');
      expect(
        await state.storage.read(key: 'deepgram_api_key'),
        'deepgram-secret',
      );
      expect(state.config.token, 'gemini-secret');

      final restored = AssistantState();
      await restored.initialize();
      expect(restored.openAiApiKey, 'openai-secret');
      expect(restored.geminiApiKey, 'gemini-secret');
      expect(restored.deepgramApiKey, 'deepgram-secret');
      await restored.clearCloudProviderKey('openai');
      expect(await restored.storage.read(key: 'openai_api_key'), isNull);
      expect(
        await restored.storage.read(key: 'gemini_api_key'),
        'gemini-secret',
      );
      state.dispose();
      restored.dispose();
    },
  );
}
