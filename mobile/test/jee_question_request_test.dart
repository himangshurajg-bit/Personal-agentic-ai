import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/jee_question_request.dart';

void main() {
  test('parses explicit JEE command forms case-insensitively', () {
    expect(
      JeeQuestionRequest.fromMessage('/jee electrostatics')?.topic,
      'electrostatics',
    );
    expect(
      JeeQuestionRequest.fromMessage(' /JEE: rotational motion ')?.topic,
      'rotational motion',
    );
    expect(JeeQuestionRequest.fromMessage('/jee'), isNull);
    expect(
      JeeQuestionRequest.fromMessage('practice jee electrostatics'),
      isNull,
    );
  });

  test(
    'prompt asks for original practice and rejects invented PYQ provenance',
    () {
      final prompt = JeeQuestionRequest('electrostatics').buildPrompt();
      expect(prompt, contains('exactly 8 numbered problems'));
      expect(
        prompt,
        contains('Generated JEE-style practice — not verified PYQs.'),
      );
      expect(
        prompt,
        contains(
          'Do not say or imply any generated problem appeared in an exam',
        ),
      );
      expect(prompt, contains('do not fabricate a confident answer'));
    },
  );
}
