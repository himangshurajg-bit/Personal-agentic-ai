/// Parses an explicitly numbered original-practice set from a saved lesson.
class StudyPracticeItem {
  final int number;
  final String question;
  final String explanation;
  final String? hint;

  const StudyPracticeItem({
    required this.number,
    required this.question,
    required this.explanation,
    this.hint,
  });
}

class StudyPractice {
  static final _numbered = RegExp(r'^\s*(\d+)[.)]\s+(.+?)\s*$');

  static List<StudyPracticeItem> parse(String lesson) {
    final lines = lesson.split('\n');
    final check = lines.indexWhere(
      (line) => line.trim().toLowerCase() == '## check your understanding',
    );
    final answers = lines.indexWhere(
      (line) => line.trim().toLowerCase() == '## answers and reasoning',
    );
    if (check < 0 || answers <= check) return const [];

    final questions = _numberedSections(lines, check + 1, answers);
    final solutions = _numberedSections(lines, answers + 1, lines.length);
    return [
      for (final entry in questions.entries)
        if (entry.value.trim().isNotEmpty &&
            (solutions[entry.key]?.trim().isNotEmpty ?? false))
          StudyPracticeItem(
            number: entry.key,
            question: _question(entry.value).$1,
            hint: _question(entry.value).$2,
            explanation: solutions[entry.key]!.trim(),
          ),
    ];
  }

  static (String, String?) _question(String raw) {
    final match = RegExp(
      r'^\s*hint:\s*(.+)$',
      multiLine: true,
      caseSensitive: false,
    ).firstMatch(raw);
    if (match == null) return (raw.trim(), null);
    final question = raw.replaceFirst(match.group(0)!, '').trim();
    return (question, match.group(1)!.trim());
  }

  static Map<int, String> _numberedSections(
    List<String> lines,
    int start,
    int end,
  ) {
    final sections = <int, String>{};
    int? current;
    final body = StringBuffer();
    void save() {
      if (current != null) sections[current] = body.toString().trim();
    }

    for (var i = start; i < end; i++) {
      final match = _numbered.firstMatch(lines[i]);
      if (match != null) {
        save();
        current = int.tryParse(match.group(1)!);
        body
          ..clear()
          ..write(match.group(2)!);
      } else if (current != null && lines[i].trim().isNotEmpty) {
        body.write('\n${lines[i].trim()}');
      }
    }
    save();
    return sections;
  }
}
