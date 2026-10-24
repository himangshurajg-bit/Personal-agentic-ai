import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_assistant/assistant_state.dart';
import 'package:personal_assistant/offline_voice.dart';
import 'package:personal_assistant/provider_compare.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  group('provider compare', () {
    test(
      'approval is mandatory and rejected runs make zero requests',
      () async {
        var calls = 0;
        final service = ProviderCompareService(
          () => MockClient((_) async {
            calls++;
            return http.Response('{}', 200);
          }),
        );
        final profiles = AIProviderProfile.defaults()
            .take(2)
            .map((p) => p.copyWith(model: 'test-model', apiKey: 'test-key'))
            .toList();
        await expectLater(
          service.run(
            profiles: profiles,
            prompt: 'exact prompt',
            approvedThisRun: false,
          ),
          throwsA(isA<ProviderCompareException>()),
        );
        expect(calls, 0);
      },
    );

    test(
      'validates every selected endpoint before starting any request',
      () async {
        var calls = 0;
        final service = ProviderCompareService(
          () => MockClient((_) async {
            calls++;
            return http.Response('{}', 200);
          }),
        );
        final profiles = [
          AIProviderProfile.defaults()[0].copyWith(model: 'model', apiKey: 'k'),
          AIProviderProfile.defaults()[1].copyWith(
            origin: 'http://unsafe.invalid/v1',
            model: 'model',
            apiKey: 'k',
          ),
        ];
        await expectLater(
          service.run(profiles: profiles, prompt: 'hi', approvedThisRun: true),
          throwsA(isA<ProviderCompareException>()),
        );
        expect(calls, 0);
      },
    );

    test(
      'provider endpoints and credentials persist only through secure storage',
      () async {
        final state = AssistantState();
        final profiles = AIProviderProfile.defaults()
            .map(
              (p) =>
                  p.copyWith(model: 'model-${p.id}', apiKey: 'secret-${p.id}'),
            )
            .toList();
        await state.saveProviderProfiles(profiles);
        const secure = FlutterSecureStorage();
        final stored = await secure.read(key: 'ai_provider_profiles');
        expect(stored, contains('secret-gemini'));
        expect(
          state.providerProfiles.map((p) => p.model),
          profiles.map((p) => p.model),
        );
        final restored = AIProviderProfile.fromSecureJson(stored);
        expect(restored.first.apiKey, 'secret-gemini');
        expect(restored.last.apiKey, 'secret-openrouter');
      },
    );

    test('Gemini uses native contents API and keeps key out of URL', () {
      final profile = AIProviderProfile.defaults().first.copyWith(
        model: 'gemini-test',
        apiKey: 'not-a-real-secret',
      );
      final request = profile.request('same text');
      expect(request.url.path, '/v1beta/models/gemini-test:generateContent');
      expect(request.url.query, isEmpty);
      expect(request.headers['x-goog-api-key'], 'not-a-real-secret');
      expect(
        jsonDecode(request.body)['contents'][0]['parts'][0]['text'],
        'same text',
      );
      expect(
        profile.parseResponse({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'Gemini answer'},
                ],
              },
            },
          ],
        }),
        'Gemini answer',
      );
    });

    test('selected providers receive the same prompt concurrently and stay separate', () async {
      var inFlight = 0;
      var peakInFlight = 0;
      final prompts = <String>[];
      final profiles = [
        AIProviderProfile.defaults()[0].copyWith(
          model: 'gemini-test',
          apiKey: 'k1',
        ),
        AIProviderProfile.defaults()[1].copyWith(
          model: 'openai-test',
          apiKey: 'k2',
        ),
      ];
      final service = ProviderCompareService(
        () => MockClient((request) async {
          inFlight++;
          if (inFlight > peakInFlight) peakInFlight = inFlight;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final prompt = request.url.host == 'generativelanguage.googleapis.com'
              ? (body['contents'] as List).first['parts'][0]['text'] as String
              : (body['messages'] as List).first['content'] as String;
          prompts.add(prompt);
          await Future<void>.delayed(const Duration(milliseconds: 20));
          inFlight--;
          final response =
              request.url.host == 'generativelanguage.googleapis.com'
              ? {
                  'candidates': [
                    {
                      'content': {
                        'parts': [
                          {'text': 'Gemini result'},
                        ],
                      },
                    },
                  ],
                }
              : {
                  'choices': [
                    {
                      'message': {'content': 'OpenAI result'},
                    },
                  ],
                };
          return http.Response(jsonEncode(response), 200);
        }),
      );
      final results = await service.run(
        profiles: profiles,
        prompt: 'one exact prompt',
        approvedThisRun: true,
      );
      expect(peakInFlight, 2);
      expect(prompts, ['one exact prompt', 'one exact prompt']);
      expect(results.map((r) => r.answer), ['Gemini result', 'OpenAI result']);
    });

    test('provider errors are generic and not automatically retried', () async {
      var calls = 0;
      final profile = AIProviderProfile.defaults()[0].copyWith(
        model: 'gemini-test',
        apiKey: 'private-key-marker',
      );
      final service = ProviderCompareService(
        () => MockClient((_) async {
          calls++;
          return http.Response('private-key-marker leaked by server', 401);
        }),
      );
      final results = await service.run(
        profiles: [
          profile,
          AIProviderProfile.defaults()[1].copyWith(model: 'm', apiKey: 'k'),
        ],
        prompt: 'hello',
        approvedThisRun: true,
      );
      expect(calls, 2);
      expect(results.first.error, contains('401'));
      expect(results.first.error, isNot(contains('private-key-marker')));
    });
  });

  test('offline Gemma voice accepts only complete local Gemma replies', () {
    const gemmaReply = {
      'role': 'assistant',
      'state': 'complete',
      'engine': 'offline',
      'text': 'local answer',
    };
    expect(isEligibleForOfflineGemmaSpeech(gemmaReply, optedIn: true), isTrue);
    expect(
      isEligibleForOfflineGemmaSpeech(gemmaReply, optedIn: false),
      isFalse,
    );
    expect(
      isEligibleForOfflineGemmaSpeech({
        ...gemmaReply,
        'engine': 'compatible',
      }, optedIn: true),
      isFalse,
    );
    expect(
      isEligibleForOfflineGemmaSpeech({
        ...gemmaReply,
        'state': 'interrupted',
      }, optedIn: true),
      isFalse,
    );
    expect(
      isEligibleForOfflineGemmaSpeech(
        {...gemmaReply}..remove('engine'),
        optedIn: true,
      ),
      isFalse,
    );
  });

  test('offline voices prefer declared quality, honor saved choice and fall back locally', () {
    final voices = [
      {
        'name': 'network best',
        'locale': 'hi-IN',
        'network_required': '1',
        'quality': 'very high',
      },
      {
        'name': 'offline normal',
        'locale': 'hi_IN',
        'network_required': false,
        'quality': 'normal',
      },
      {
        'name': 'offline best',
        'locale': 'hi-IN',
        'network_required': 0,
        'quality': 'very high',
        'latency': 'low',
      },
      {
        'name': 'wrong language',
        'locale': 'en-IN',
        'network_required': 0,
        'quality': 'very high',
      },
    ];
    expect(
      installedOfflineVoices(voices, 'hi-IN').map((voice) => voice['name']),
      ['offline best', 'offline normal'],
    );
    expect(
      selectInstalledOfflineVoice(voices, 'hi-IN')?['name'],
      'offline best',
    );
    expect(
      selectInstalledOfflineVoice(
        voices,
        'hi-IN',
        preferredName: 'offline normal',
        preferredLocale: 'hi-IN',
      )?['name'],
      'offline normal',
    );
    expect(
      selectInstalledOfflineVoice(
        voices,
        'hi-IN',
        preferredName: 'removed voice',
        preferredLocale: 'hi-IN',
      )?['name'],
      'offline best',
    );
    expect(selectInstalledOfflineVoice(voices, 'as-IN'), isNull);
    expect(
      offlineVoiceOptionLabel(installedOfflineVoices(voices, 'hi-IN').first),
      contains('very high'),
    );
  });
}
