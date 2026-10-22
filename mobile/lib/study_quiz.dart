import 'dart:math';

class PracticeQuizQuestion {
  final String cardId;
  final String prompt;
  final String answer;
  final List<String> choices;

  const PracticeQuizQuestion({
    required this.cardId,
    required this.prompt,
    required this.answer,
    required this.choices,
  });
}

/// Builds deterministic answer-key questions from the learner's own saved cards.
/// It neither generates content nor changes the spaced-repetition schedule.
List<PracticeQuizQuestion> buildPracticeQuiz(
  List<Map<String, dynamic>> cards, {
  Random? random,
  int limit = 8,
}) {
  final rng = random ?? Random();
  final usable = _usablePracticeCards(cards);
  final answers = usable.map((card) => card['back'].toString().trim()).toSet();
  if (usable.length < 2 || answers.length < 2 || limit < 1) return const [];
  usable.shuffle(rng);
  return usable.take(limit).map((card) {
    final answer = card['back'].toString().trim();
    final alternatives =
        usable
            .map((other) => other['back'].toString().trim())
            .where((other) => other != answer)
            .toSet()
            .toList()
          ..shuffle(rng);
    final choices = [answer, ...alternatives.take(3)]..shuffle(rng);
    return PracticeQuizQuestion(
      cardId: card['id'].toString(),
      prompt: card['front'].toString().trim(),
      answer: answer,
      choices: choices,
    );
  }).toList();
}

List<Map<String, dynamic>> _usablePracticeCards(
  List<Map<String, dynamic>> cards,
) => cards.where((card) {
  return card['id'] is String &&
      card['front'] is String &&
      card['front'].toString().trim().isNotEmpty &&
      card['back'] is String &&
      card['back'].toString().trim().isNotEmpty;
}).toList();

bool canBuildPracticeQuiz(List<Map<String, dynamic>> cards) {
  final usable = _usablePracticeCards(cards);
  return usable.length >= 2 &&
      usable.map((card) => card['back'].toString().trim()).toSet().length >= 2;
}
