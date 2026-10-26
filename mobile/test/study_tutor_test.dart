import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/study_tutor.dart';

void main() {
  test('Ask tutor prompt includes the selected style and learner material', () {
    final prompt = StudyTutor.request(
      style: 'Hints first',
      topic: 'Newton’s second law',
      question: 'Why divide by mass?',
    );

    expect(
      prompt,
      startsWith(
        'Learning preference: Hints first. Topic: Newton’s second law.',
      ),
    );
    expect(prompt, contains('Question / task: Why divide by mass?'));
    expect(prompt, isNot(contains('STUDY TUTORING')));
  });

  test('tutoring contract honors short answers and exam-source accuracy', () {
    expect(StudyTutor.generationInstruction, contains('just the answer'));
    expect(
      StudyTutor.generationInstruction,
      contains('unless a verified source is supplied'),
    );
    expect(
      StudyTutor.generationInstruction,
      contains('label generated questions as original practice'),
    );
    expect(
      StudyTutor.generationInstruction,
      contains(
        'build on earlier explanation only when that context is actually supplied',
      ),
    );
  });
}
