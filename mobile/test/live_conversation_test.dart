import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/live_conversation.dart';

void main() {
  group('Deepgram live transcript parser', () {
    test('holds interim speech and joins finalized segments at endpoint', () {
      final parser = DeepgramLiveTranscriptParser();

      expect(
        parser.addMessage(
          jsonEncode({
            'type': 'Results',
            'is_final': false,
            'speech_final': false,
            'channel': {
              'alternatives': [
                {'transcript': 'Hello'},
              ],
            },
          }),
        ),
        isNull,
      );
      expect(
        parser.addMessage(
          jsonEncode({
            'type': 'Results',
            'is_final': true,
            'speech_final': false,
            'channel': {
              'alternatives': [
                {'transcript': 'Hello there'},
              ],
            },
          }),
        ),
        isNull,
      );
      expect(
        parser.addMessage(
          jsonEncode({
            'type': 'Results',
            'is_final': true,
            'speech_final': true,
            'channel': {
              'alternatives': [
                {'transcript': 'how are you'},
              ],
            },
          }),
        ),
        'Hello there how are you',
      );
      expect(parser.addMessage(jsonEncode({'type': 'UtteranceEnd'})), isNull);
    });

    test(
      'utterance-end flushes retained final segments and reset discards them',
      () {
        final parser = DeepgramLiveTranscriptParser();
        final finalSegment = jsonEncode({
          'type': 'Results',
          'is_final': true,
          'speech_final': false,
          'channel': {
            'alternatives': [
              {'transcript': 'অসমীয়া কথা'},
            ],
          },
        });
        expect(parser.addMessage(finalSegment), isNull);
        expect(
          parser.addMessage(jsonEncode({'type': 'UtteranceEnd'})),
          'অসমীয়া কথা',
        );
        expect(parser.addMessage(finalSegment), isNull);
        parser.reset();
        expect(parser.addMessage(jsonEncode({'type': 'UtteranceEnd'})), isNull);
      },
    );

    test(
      'supported live speech locales include English, Assamese and Hindi',
      () {
        expect(DeepgramLiveSession.supportedLocales, {
          'en-IN',
          'as-IN',
          'hi-IN',
        });
      },
    );
  });
}
