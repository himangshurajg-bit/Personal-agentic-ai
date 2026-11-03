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
    test('app launch parsing is explicit and rejects unrelated commands', () {
      expect(SpokenAppLaunch.parse('open the calculator')?.name, 'calculator');
      expect(SpokenAppLaunch.parse('Please launch Maps')?.name, 'Maps');
      expect(SpokenAppLaunch.parse('send a message to Alex'), isNull);
      expect(SpokenAppLaunch.parse('open '), isNull);
    });
    test('web search parser accepts only explicit bounded search requests', () {
      expect(
        SpokenWebSearch.parse('search the web for JEE physics')?.query,
        'JEE physics',
      );
      expect(
        SpokenWebSearch.parse('please look up weather in Guwahati')?.query,
        'weather in Guwahati',
      );
      expect(SpokenWebSearch.parse('search for '), isNull);
      expect(SpokenWebSearch.parse('what should I search for?'), isNull);
    });
    test(
      'message draft parser requires explicit recipient and message body',
      () {
        final draft = SpokenMessageDraft.parse(
          'message Alex saying I will be late',
        );
        expect(draft?.recipient, 'Alex');
        expect(draft?.body, 'I will be late');
        expect(
          SpokenMessageDraft.parse('send a message to Mom: I am outside')?.body,
          'I am outside',
        );
        expect(SpokenMessageDraft.parse('message Alex'), isNull);
        expect(
          SpokenMessageDraft.parse('search for a message to Alex'),
          isNull,
        );
      },
    );
    test('notification read intent is explicit and bounded', () {
      expect(isSpokenNotificationRead('read my notifications'), isTrue);
      expect(isSpokenNotificationRead('please check notifications'), isTrue);
      expect(isSpokenNotificationRead('read all messages from Mom'), isFalse);
    });
    test('torch-off voice command is exact and never activates the flash', () {
      expect(isSpokenTorchOffCommand('turn off the flashlight'), isTrue);
      expect(isSpokenTorchOffCommand('please switch the torch off'), isTrue);
      expect(isSpokenTorchOffCommand('turn off my phone flashlight'), isTrue);
      expect(isSpokenTorchOffCommand('turn on the flashlight'), isFalse);
      expect(isSpokenTorchOffCommand('is my flashlight on?'), isFalse);
      expect(isSpokenTorchOffCommand('turn the flashlight on'), isFalse);
    });
    test(
      'playback interruption stops speech without ending the session',
      () async {
        var stopped = false;
        final playback = AudioPlaybackManager(() async => stopped = true);
        await playback.interrupt();
        expect(stopped, isTrue);
      },
    );
  });
}
