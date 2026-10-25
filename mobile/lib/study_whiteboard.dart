/// Prompting contract for lessons rendered and saved to the Study Whiteboard.
/// It deliberately distinguishes generated exam-style work from verified PYQs.
class StudyWhiteboard {
  static bool isLessonResponse(String response) =>
      response.trimLeft().startsWith('## Topic explanation');

  static const String generationInstruction = '''
STUDY WHITEBOARD MODE: Treat the student's latest message as a topic or learning question. Give a clear, accurate concept explanation, a short worked example when useful, then an automatically generated progressive practice set. For a learning topic, start the reply immediately with this exact Markdown heading (no preamble); for non-topic messages, do not use it. Use these Markdown headings in order:
## Topic explanation
## Worked example
## Basic foundations
## JEE Main practice
## JEE Advanced practice
## Answers and reasoning
Make eight topic-specific questions: two foundational, three JEE Main level (easy to hard), and three JEE Advanced level (multi-step / very challenging). Include the complete answer and a concise, checkable step-by-step reason for every question, with units and assumptions where relevant. Keep question numbering stable so each solution clearly matches its question.
IMPORTANT SOURCE ACCURACY: Unless the user included a verifiable past-paper question/source in the prompt, these must be clearly identified as original JEE-style practice, not exact previous-year questions. Never invent an exam year, paper, question number, source, or claim that original generated text is an official PYQ. At the end state briefly that no verified PYQ source was supplied, if applicable. If the message is not a learning topic, answer it briefly without manufacturing a quiz. Do not claim an answer was independently checked.''';
}
