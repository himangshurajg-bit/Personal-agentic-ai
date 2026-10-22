import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/study_quiz.dart';

void main() {
  final cards = [
    {'id': '1', 'front': '2 + 2?', 'back': '4'},
    {'id': '2', 'front': 'Capital of France?', 'back': 'Paris'},
    {'id': '3', 'front': 'Largest planet?', 'back': 'Jupiter'},
  ];

  test('builds quiz from saved flashcards without changing source records', () {
    final before = cards.map((card) => Map<String, dynamic>.of(card)).toList();
    final quiz = buildPracticeQuiz(cards, limit: 2);
    expect(quiz, hasLength(2));
    for (final question in quiz) {
      expect(question.prompt, isNotEmpty);
      expect(question.choices, contains(question.answer));
      expect(question.choices.toSet(), hasLength(question.choices.length));
      expect(question.choices.length, greaterThanOrEqualTo(2));
      expect(question.choices.length, lessThanOrEqualTo(4));
    }
    expect(cards, before);
  });

  test('does not claim a quiz when answers are not distinguishable', () {
    final repeated = [
      {'id': '1', 'front': 'Term one', 'back': 'Same'},
      {'id': '2', 'front': 'Term two', 'back': 'Same'},
    ];
    expect(canBuildPracticeQuiz(repeated), isFalse);
    expect(buildPracticeQuiz(repeated), isEmpty);
    expect(buildPracticeQuiz(cards, limit: 0), isEmpty);
  });
}
