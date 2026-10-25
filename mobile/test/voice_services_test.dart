import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:personal_assistant/assistant_state.dart';
import 'package:personal_assistant/voice_services.dart';

void main() {
  final audio = Uint8List.fromList([1, 2, 3, 4]);
  final success = jsonEncode({
    'results': {
      'channels': [
        {
          'alternatives': [
            {'transcript': '  Hello there.  '},
          ],
        },
      ],
    },
  });

  test(
    'Azure TTS sends escaped English or Hindi SSML to the selected region',
    () async {
      late http.Request observed;
      final service = AzureSpeechSynthesizer(
        clientFactory: () => MockClient((request) async {
          observed = request;
          return http.Response.bytes([0x49, 0x44, 0x33, 1], 200);
        }),
      );
      final audio = await service.synthesize(
        text: 'Hello <friend> & welcome',
        apiKey: 'azure-key-not-for-logs',
        region: 'centralindia',
        locale: 'en-IN',
        rate: 0.5,
      );
      expect(audio, [0x49, 0x44, 0x33, 1]);
      expect(
        observed.url.origin,
        'https://centralindia.tts.speech.microsoft.com',
      );
      expect(observed.url.path, '/cognitiveservices/v1');
      expect(observed.url.query, isEmpty);
      expect(
        observed.headers['Ocp-Apim-Subscription-Key'],
        'azure-key-not-for-logs',
      );
      expect(
        observed.headers['Content-Type']!.startsWith('application/ssml+xml'),
        isTrue,
      );
      expect(
        observed.headers['X-Microsoft-OutputFormat'],
        'audio-24khz-48kbitrate-mono-mp3',
      );
      expect(observed.body, contains('en-IN-NeerjaNeural'));
      expect(observed.body, contains('Hello &lt;friend&gt; &amp; welcome'));
      expect(observed.body, contains('rate="100%"'));
    },
  );

  test('Azure TTS rejects missing credentials, bad region and non-English/Hindi before networking', () async {
    var calls = 0;
    final service = AzureSpeechSynthesizer(
      clientFactory: () => MockClient((_) async {
        calls++;
        return http.Response.bytes([1], 200);
      }),
    );
    Future<Uint8List> run({
      String key = 'key',
      String region = 'eastus',
      String locale = 'en-IN',
    }) => service.synthesize(
      text: 'Hello',
      apiKey: key,
      region: region,
      locale: locale,
      rate: .5,
    );
    await expectLater(run(key: ''), throwsA(isA<ServiceException>()));
    await expectLater(
      run(region: 'eastus.attacker.example'),
      throwsA(isA<ServiceException>()),
    );
    await expectLater(run(locale: 'as-IN'), throwsA(isA<ServiceException>()));
    await expectLater(
      run(locale: 'hi-Latn-IN'),
      throwsA(isA<ServiceException>()),
    );
    expect(calls, 0);
  });

  test('Azure quota/provider failure is surfaced without response content or retry', () async {
    var calls = 0;
    final service = AzureSpeechSynthesizer(
      clientFactory: () => MockClient((_) async {
        calls++;
        return http.Response('private provider response', 429);
      }),
    );
    await expectLater(
      service.synthesize(
        text: 'Hello',
        apiKey: 'private-key',
        region: 'eastus',
        locale: 'hi-IN',
        rate: .5,
      ),
      throwsA(
        predicate(
          (error) =>
              error is ServiceException &&
              error.toString().contains('quota') &&
              !error.toString().contains('private provider response') &&
              !error.toString().contains('private-key'),
        ),
      ),
    );
    expect(calls, 1);
  });

  test(
    'Gemini expressive TTS sends verbatim text, style, voice and API key',
    () async {
      final wav = Uint8List.fromList([
        ...ascii.encode('RIFF'),
        ...List<int>.filled(4, 0),
        ...ascii.encode('WAVE'),
        ...List<int>.filled(32, 0),
      ]);
      late http.Request observed;
      final service = GeminiExpressiveSpeechSynthesizer(
        clientFactory: () => MockClient((request) async {
          observed = request;
          return http.Response(
            jsonEncode({
              'steps': [
                {
                  'content': [
                    {'type': 'audio', 'data': base64Encode(wav)},
                  ],
                },
              ],
            }),
            200,
          );
        }),
      );
      final output = await service.synthesize(
        text: '  Hello <friend>  ',
        apiKey: 'existing-gemini-key',
        locale: 'as-IN',
        style: GeminiExpressiveSpeechSynthesizer.styleFor('angry'),
      );
      expect(output, wav);
      expect(
        observed.url,
        Uri.parse(GeminiExpressiveSpeechSynthesizer.endpoint),
      );
      expect(observed.headers['x-goog-api-key'], 'existing-gemini-key');
      expect(observed.headers['content-type'], 'application/json');
      final body = jsonDecode(observed.body) as Map<String, dynamic>;
      expect(body['model'], GeminiExpressiveSpeechSynthesizer.model);
      expect(body['response_format'], {
        'type': 'audio',
        'mime_type': 'audio/wav',
      });
      expect(body['generation_config'], {
        'speech_config': [
          {'voice': 'Kore'},
        ],
      });
      final input = (body['input'] as List).single as Map<String, dynamic>;
      expect(input['text'], 'Hello <friend>');
      expect(input['annotations'], [
        {
          'type': 'speech_metadata',
          'style': GeminiExpressiveSpeechSynthesizer.styleFor('angry'),
        },
      ]);
    },
  );

  test('Gemini TTS rejects empty key, unsupported language and empty text before networking', () async {
    var calls = 0;
    final service = GeminiExpressiveSpeechSynthesizer(
      clientFactory: () => MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    Future<Uint8List> run({
      String key = 'key',
      String locale = 'en-IN',
      String text = 'Hello',
    }) => service.synthesize(text: text, apiKey: key, locale: locale);
    await expectLater(run(key: ''), throwsA(isA<ServiceException>()));
    await expectLater(
      run(locale: 'hi-Latn-IN'),
      throwsA(isA<ServiceException>()),
    );
    await expectLater(run(text: '  '), throwsA(isA<ServiceException>()));
    expect(calls, 0);
  });

  test('Gemini TTS provider failure is safe and never retried', () async {
    var calls = 0;
    final service = GeminiExpressiveSpeechSynthesizer(
      clientFactory: () => MockClient((_) async {
        calls++;
        return http.Response('private response and key', 429);
      }),
    );
    await expectLater(
      service.synthesize(text: 'Hello', apiKey: 'private-key', locale: 'en-IN'),
      throwsA(
        predicate(
          (error) =>
              error is ServiceException &&
              error.toString().contains('quota') &&
              !error.toString().contains('private response') &&
              !error.toString().contains('private-key'),
        ),
      ),
    );
    expect(calls, 1);
  });

  test(
    'refuses a missing key and unsupported locale before networking',
    () async {
      var calls = 0;
      final service = DeepgramTranscriber(
        clientFactory: () => MockClient((_) async {
          calls++;
          return http.Response(success, 200);
        }),
      );
      await expectLater(
        service.transcribe(pcm16le: audio, apiKey: '', locale: 'en-IN'),
        throwsA(isA<ServiceException>()),
      );
      await expectLater(
        service.transcribe(pcm16le: audio, apiKey: 'secret', locale: 'as-IN'),
        throwsA(isA<ServiceException>()),
      );
      expect(calls, 0);
    },
  );

  test('sends foreground PCM only to Deepgram and parses transcript', () async {
    late http.Request observed;
    final service = DeepgramTranscriber(
      clientFactory: () => MockClient((request) async {
        observed = request;
        return http.Response(success, 200);
      }),
    );
    expect(
      await service.transcribe(
        pcm16le: audio,
        apiKey: 'private-key',
        locale: 'hi-IN',
      ),
      'Hello there.',
    );
    expect(observed.url.origin, 'https://api.deepgram.com');
    expect(observed.url.path, '/v1/listen');
    expect(observed.url.queryParameters['model'], 'nova-3');
    expect(observed.url.queryParameters['language'], 'hi');
    expect(observed.headers['authorization'], 'Token private-key');
    expect(observed.headers['content-type'], 'audio/raw');
    expect(observed.bodyBytes, audio);
  });

  test('provider errors do not expose response content or retry', () async {
    var calls = 0;
    final service = DeepgramTranscriber(
      clientFactory: () => MockClient((_) async {
        calls++;
        return http.Response('secret response body', 401);
      }),
    );
    await expectLater(
      service.transcribe(
        pcm16le: audio,
        apiKey: 'private-key',
        locale: 'en-IN',
      ),
      throwsA(
        predicate(
          (error) =>
              error is ServiceException && !error.toString().contains('secret'),
        ),
      ),
    );
    expect(calls, 1);
  });

  test('cancellation invalidates a pending transcription', () async {
    final client = _DeferredClient();
    final service = DeepgramTranscriber(clientFactory: () => client);
    final result = service.transcribe(
      pcm16le: audio,
      apiKey: 'private-key',
      locale: 'en-IN',
    );
    await Future<void>.delayed(Duration.zero);
    service.cancel();
    client.response.complete(
      http.StreamedResponse(Stream.value(utf8.encode(success)), 200),
    );
    await expectLater(result, throwsA(isA<ServiceException>()));
    expect(client.closed, isTrue);
  });
}

class _DeferredClient extends http.BaseClient {
  final response = Completer<http.StreamedResponse>();
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      response.future;
  @override
  void close() => closed = true;
}
