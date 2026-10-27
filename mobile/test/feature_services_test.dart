import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:personal_assistant/feature_services.dart';

void main() {
  group('Gemini document requests', () {
    test(
      'includes the selected PDF bytes and prompt only in the reviewed request',
      () {
        final client = GeminiFeatureClient(
          model: 'gemini-3.5-flash-lite',
          apiKey: 'test-key',
          clientFactory: () =>
              MockClient((_) async => throw StateError('not sent')),
        );
        final request = client.documentRequest(
          mimeType: 'application/pdf',
          bytes: Uint8List.fromList([0, 1, 2, 253, 254, 255]),
          prompt: 'Summarize this file',
        );
        expect(
          request.url.path,
          endsWith('/gemini-3.5-flash-lite:generateContent'),
        );
        expect(request.headers['x-goog-api-key'], 'test-key');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final parts =
            ((body['contents'] as List).single as Map)['parts'] as List;
        expect((parts[0] as Map)['text'], 'Summarize this file');
        expect((parts[1] as Map)['inline_data'], {
          'mime_type': 'application/pdf',
          'data': base64Encode([0, 1, 2, 253, 254, 255]),
        });
      },
    );

    test(
      'rejects unsupported MIME and oversize documents before request creation',
      () {
        final client = GeminiFeatureClient(
          model: 'gemini-3.5-flash-lite',
          apiKey: 'test-key',
          clientFactory: () =>
              MockClient((_) async => throw StateError('not sent')),
        );
        expect(
          () => client.documentRequest(
            mimeType: 'text/plain',
            bytes: Uint8List.fromList([1]),
            prompt: 'Explain',
          ),
          throwsA(isA<FeatureServiceException>()),
        );
        expect(
          () => client.documentRequest(
            mimeType: 'image/png',
            bytes: Uint8List(maxAiDocumentBytes + 1),
            prompt: 'Explain',
          ),
          throwsA(isA<FeatureServiceException>()),
        );
      },
    );
  });

  group('Gemini web research', () {
    test('times out if the response body stalls after headers', () async {
      final stalledClient = _StalledBodyClient();
      final client = GeminiFeatureClient(
        model: 'gemini-3.5-flash-lite',
        apiKey: 'test-key',
        requestTimeout: const Duration(milliseconds: 30),
        clientFactory: () => stalledClient,
      );

      await expectLater(
        client.research('What is a test?'),
        throwsA(
          isA<FeatureServiceException>().having(
            (error) => error.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
      expect(stalledClient.closed, isTrue);
    });

    test('requests Google Search grounding and surfaces only returned HTTPS sources', () async {
      final client = GeminiFeatureClient(
        model: 'gemini-3.5-flash-lite',
        apiKey: 'test-key',
        clientFactory: () => MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['tools'], [
            {'google_search': <String, dynamic>{}},
          ]);
          final prompt =
              (((body['contents'] as List).single as Map)['parts'] as List)
                      .single
                  as Map;
          expect(prompt['text'], contains('broadly using Google Search'));
          expect(
            prompt['text'],
            contains('Do not claim the search is exhaustive'),
          );
          expect(request.headers['x-goog-api-key'], 'test-key');
          return httpResponse({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'A grounded answer.'},
                  ],
                },
                'groundingMetadata': {
                  'groundingChunks': [
                    {
                      'web': {
                        'uri': 'https://example.org/article',
                        'title': 'Example source',
                      },
                    },
                    {
                      'web': {'uri': 'javascript:alert(1)', 'title': 'Unsafe'},
                    },
                  ],
                  'groundingSupports': [
                    {
                      'segment': {'text': 'A grounded answer.'},
                      'groundingChunkIndices': [0],
                    },
                  ],
                  'webSearchQueries': [
                    'test definition',
                    'test definition',
                    'testing standards',
                    '',
                    42,
                  ],
                },
              },
            ],
          });
        }),
      );
      final result = await client.research('What is a test?');
      expect(result.text, 'A grounded answer.');
      expect(result.searchQueries, ['test definition', 'testing standards']);
      expect(result.sources, hasLength(1));
      expect(
        result.sources.single.uri.toString(),
        'https://example.org/article',
      );
      expect(result.sources.single.supportingText, 'A grounded answer.');
    });

    test('does not treat a URL in model prose as a source', () {
      final result = FeatureAnswer.fromGenerateContent({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'See https://made-up.example/fake for more.'},
              ],
            },
          },
        ],
      });
      expect(result.sources, isEmpty);
    });
  });

  group('voice command review parser', () {
    test('recognizes allowlisted app navigation', () {
      final command = VoiceFeatureCommand.parse('Please open Study!');
      expect(command.kind, VoiceFeatureCommandKind.openRoute);
      expect(command.route, '/study');
    });

    test('opens web research directly in its selected tab', () {
      final command = VoiceFeatureCommand.parse('open research');
      expect(command.kind, VoiceFeatureCommandKind.openRoute);
      expect(command.route, '/features/research');
    });

    test('extracts reminder description but does not infer its time', () {
      final command = VoiceFeatureCommand.parse(
        'Remind me to revise chemistry',
      );
      expect(command.kind, VoiceFeatureCommandKind.reminder);
      expect(command.title, 'revise chemistry');
      expect(command.route, isNull);
    });

    test('unknown and unsupported commands remain inert', () {
      expect(
        VoiceFeatureCommand.parse('send the message now').kind,
        VoiceFeatureCommandKind.unsupported,
      );
      expect(
        VoiceFeatureCommand.parse('open unknown app').kind,
        VoiceFeatureCommandKind.unsupported,
      );
    });
  });
}

http.Response httpResponse(Map<String, dynamic> body) =>
    http.Response(jsonEncode(body), 200);

class _StalledBodyClient extends http.BaseClient {
  StreamController<List<int>>? _body;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    _body = StreamController<List<int>>();
    return http.StreamedResponse(_body!.stream, 200);
  }

  @override
  void close() {
    closed = true;
    final body = _body;
    if (body != null && !body.isClosed) unawaited(body.close());
  }
}
