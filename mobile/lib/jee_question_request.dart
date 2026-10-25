/// Turns an explicit `/jee <topic>` chat command into a source-honest practice set.
///
/// This deliberately does not fetch or claim real past-year questions. The app has
/// no verified PYQ corpus attached to this request, so the provider is asked only
/// for original JEE-style practice.
class JeeQuestionRequest {
  const JeeQuestionRequest(this.topic);

  final String topic;

  static JeeQuestionRequest? fromMessage(String message) {
    final match = RegExp(
      r'^\s*/jee(?:\s+|:\s*)([\s\S]+?)\s*$',
      caseSensitive: false,
    ).firstMatch(message);
    final topic = match?.group(1)?.trim();
    if (topic == null || topic.isEmpty) return null;
    return JeeQuestionRequest(topic);
  }

  /// This entire text is displayed in the online-send review before transmission.
  String buildPrompt() =>
      '''Create an original JEE practice set for this topic: "$topic".

Return exactly 8 numbered problems, grouped in this order:
1. Foundational / basic (2 problems)
2. Developing / intermediate (2 problems)
3. JEE Main style (2 problems)
4. High-challenge JEE Advanced style (2 problems)

For every problem, include:
- the full question and any needed data;
- a clearly marked final answer;
- a step-by-step reasoning/explanation that shows the key idea, assumptions and units where relevant.
Use a sensible mix of conceptual and calculation-based questions when the subject permits. Make each problem solvable from the information given, and check the reasoning and answer for internal consistency. If the topic is ambiguous, state a brief assumption rather than silently changing it.

Provenance and accuracy:
- Label the set: "Generated JEE-style practice — not verified PYQs."
- No authoritative JEE Main/JEE Advanced past-year source material is attached. Do not say or imply any generated problem appeared in an exam, identify it as a PYQ, or invent an exam year/source.
- Create original practice problems inspired by the exam's general style only. Do not present generated examples as retrieved or verified past questions.
- If you cannot solve a problem confidently, say so and replace it with a solvable one; do not fabricate a confident answer.''';
}
