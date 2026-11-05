import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/live_conversation_speech.dart';

void main() {
  test(
    'emits sentence chunks from cumulative streaming text without repeats',
    () {
      final buffer = LiveConversationSpeechBuffer();
      expect(buffer.add('Hello there. How are'), ['Hello there.']);
      expect(buffer.add('Hello there. How are you?'), ['How are you?']);
      expect(buffer.add('Hello there. How are you?', flush: true), isEmpty);
    },
  );

  test('flushes an unpunctuated final response and strips markup', () {
    final buffer = LiveConversationSpeechBuffer();
    expect(buffer.add('**A short answer**', flush: true), ['A short answer']);
  });

  test('keeps very long unpunctuated output in word-bounded chunks', () {
    final buffer = LiveConversationSpeechBuffer();
    final text = List.filled(44, 'word').join(' ');
    final first = buffer.add(text);
    expect(first, isNotEmpty);
    expect(first.join(' '), isNot(contains('  ')));
    final rest = buffer.add(text, flush: true);
    expect(rest, isNotEmpty);
    expect((first + rest).join(' '), text);
  });
}
