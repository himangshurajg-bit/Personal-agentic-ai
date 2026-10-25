import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/jee_question_request.dart';

void main() {
  test(
    'explicit command extracts the full topic and ignores ordinary chat',
    () {
      expect(JeeQuestionRequest.fromMessage('Explain capacitance'), isNull);
      expect(JeeQuestionRequest.fromMessage('/jee'), isNull);
      expect(JeeQuestionRequest.fromMessage('/jee   '), isNull);
      expect(
        JeeQuestionRequest.fromMessage('  /JEE: Electrostatics  '),
        isA<JeeQuestionRequest>().having(
          (r) => r.topic,
          'topic',
          'Electrostatics',
        ),
      );
    },
  );

  test('prompt builds a balanced set without fabricating PYQ provenance', () {
    final prompt = JeeQuestionRequest.fromMessage('/jee vectors')!
        .buildPrompt();
    expect(prompt, contains('exactly 8 numbered problems'));
    expect(prompt, contains('Foundational / basic (2 problems)'));
    expect(prompt, contains('JEE Main style (2 problems)'));
    expect(prompt, contains('High-challenge JEE Advanced style (2 problems)'));
    expect(prompt, contains('final answer'));
    expect(prompt, contains('step-by-step reasoning/explanation'));
    expect(prompt, contains('not verified PYQs'));
    expect(
      prompt,
      contains(
        'No authoritative JEE Main/JEE Advanced past-year source material is attached',
      ),
    );
    expect(
      prompt,
      contains('Do not say or imply any generated problem appeared in an exam'),
    );
  });

  test('preserves a longer topic without silently truncating it', () {
    final topic = 'x' * 241;
    expect(JeeQuestionRequest.fromMessage('/jee $topic')?.topic, topic);
  });
}
