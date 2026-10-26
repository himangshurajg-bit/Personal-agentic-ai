import 'study_tutor.dart';

/// Prompting contract for lessons rendered and saved to the Study Whiteboard.
/// It deliberately distinguishes generated exam-style work from verified PYQs.
class StudyWhiteboard {
  static bool isLessonResponse(String response) =>
      response.trimLeft().startsWith('## Topic explanation');

  static const String generationInstruction =
      '''
${StudyTutor.generationInstruction}

STUDY WHITEBOARD PRESENTATION: For a new topic or a request for a full lesson, begin the answer immediately with the exact Markdown heading "## Topic explanation" (no preamble) so the lesson can be saved. Use the following headings when they fit the request, in this order: ## Topic explanation; ## Foundations; ## Build it step by step; ## Worked example; ## Advanced connection; ## Check your understanding; ## Answers and reasoning. Keep the explanation proportional to the learner's request; do not pad a short answer with empty sections. Include a small, progressively harder practice set only when useful or requested. If the learner explicitly asks for JEE practice, include suitable foundational, JEE Main, and JEE Advanced-style questions as appropriate, with solutions clearly matched by number. For a follow-up about one part of a saved lesson, answer that point directly without regenerating the full lesson or quiz; use the heading only when the learner asks for a new or rebuilt lesson. Never present generated questions as official PYQs without a verified source. If no source was supplied for an exam-style set, label it original practice, not exact previous-year questions.''';
}
