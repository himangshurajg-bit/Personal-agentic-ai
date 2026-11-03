import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:personal_assistant/assistant_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'provider key slots remain separate and legacy Deepgram secrets are purged',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'deepgram_api_key': 'legacy-secret',
        'speech_mode': 'deepgram',
        'voice_conversation_mode': 'live_conversation',
      });
      final state = AssistantState();
      await state.initialize();
      expect(await state.storage.read(key: 'deepgram_api_key'), isNull);
      expect(await state.storage.read(key: 'speech_mode'), 'offline');
      expect(
        await state.storage.read(key: 'voice_conversation_mode'),
        'live_conversation',
      );
      expect(state.voiceConversationMode, 'live_conversation');
      await expectLater(
        state.saveCloudProviderKey('deepgram', 'replacement-secret'),
        throwsA(isA<ServiceException>()),
      );
      await state.saveCloudProviderKey('openai', 'openai-secret');
      await state.saveCloudProviderKey('gemini', 'gemini-secret');
      await state.saveCloudProviderKey('azure_speech', 'azure-speech-secret');
      await state.saveAzureSpeechRegion('CentralIndia');
      expect(
        state.azureSpeechEnabled,
        isFalse,
        reason: 'online speech is opt-in',
      );
      expect(await state.storage.read(key: 'openai_api_key'), 'openai-secret');
      expect(await state.storage.read(key: 'gemini_api_key'), 'gemini-secret');
      expect(
        await state.storage.read(key: 'azure_speech_api_key'),
        'azure-speech-secret',
      );
      expect(
        await state.storage.read(key: 'azure_speech_region'),
        'centralindia',
      );
      expect(await state.storage.read(key: 'azure_speech_enabled'), isNull);
      expect(state.config.token, 'gemini-secret');

      final restored = AssistantState();
      await restored.initialize();
      expect(restored.openAiApiKey, 'openai-secret');
      expect(restored.geminiApiKey, 'gemini-secret');
      expect(restored.azureSpeechApiKey, 'azure-speech-secret');
      expect(restored.azureSpeechRegion, 'centralindia');
      expect(restored.azureSpeechEnabled, isFalse);
      await restored.saveAzureSpeechEnabled(true);
      expect(await restored.storage.read(key: 'azure_speech_enabled'), 'yes');
      await restored.clearCloudProviderKey('azure_speech');
      expect(await restored.storage.read(key: 'azure_speech_api_key'), isNull);
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
