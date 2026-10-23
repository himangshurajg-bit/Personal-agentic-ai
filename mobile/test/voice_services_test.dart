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
