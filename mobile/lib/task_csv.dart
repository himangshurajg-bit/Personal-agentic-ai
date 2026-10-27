/// Bounded CSV import/export for this app's on-device task list.
/// Imported schedule-like values are deliberately inert metadata, never actions.
class TaskCsv {
  static const headers = <String>[
    'title',
    'done',
    'due_date',
    'reminder',
    'repeat',
  ];
  static const maxRows = 500;
  static const maxCharacters = 200000;
  static const maxCellCharacters = 1000;

  static String exportRows(List<Map<String, dynamic>> tasks) {
    final rows = <List<String>>[headers];
    for (final task in tasks) {
      final metadata = task['imported_inactive_schedule_metadata'];
      final schedule = metadata is Map ? metadata : const <Object?, Object?>{};
      rows.add([
        task['title']?.toString() ?? '',
        task['done'] == true ? 'true' : 'false',
        schedule['due_date']?.toString() ?? '',
        schedule['reminder']?.toString() ?? '',
        schedule['repeat']?.toString() ?? '',
      ]);
    }
    return '${rows.map((row) => row.map(_encodeCell).join(',')).join('\r\n')}\r\n';
  }

  /// Parses a small RFC-4180-style CSV document and rejects the whole file on
  /// malformed or out-of-bound input; callers must still ask before saving.
  static List<Map<String, Object?>> parse(String text) {
    if (text.length > maxCharacters) {
      throw const FormatException(
        'CSV is larger than the 200 KB import limit.',
      );
    }
    if (text.contains('\u0000')) {
      throw const FormatException('CSV contains an invalid NUL character.');
    }
    final table = _decode(text);
    if (table.isEmpty) throw const FormatException('CSV is empty.');
    final rawHeaders = table.first
        .map((value) => value.trim().toLowerCase())
        .toList(growable: false);
    if (rawHeaders.isEmpty || rawHeaders.any((value) => value.isEmpty)) {
      throw const FormatException('CSV needs named columns in its first row.');
    }
    if (rawHeaders.toSet().length != rawHeaders.length) {
      throw const FormatException('CSV has duplicate column names.');
    }
    const allowed = {'title', 'done', 'due_date', 'reminder', 'repeat'};
    if (rawHeaders.any((header) => !allowed.contains(header)) ||
        !rawHeaders.contains('title')) {
      throw const FormatException(
        'CSV must have a title column and may include done, due_date, reminder, and repeat.',
      );
    }
    final dataRows = table
        .skip(1)
        .where((row) => row.any((cell) => cell.trim().isNotEmpty))
        .toList(growable: false);
    if (dataRows.length > maxRows) {
      throw const FormatException('CSV can import at most 500 tasks at once.');
    }
    final indexes = <String, int>{
      for (var index = 0; index < rawHeaders.length; index++)
        rawHeaders[index]: index,
    };
    String valueAt(List<String> row, String key) {
      final index = indexes[key];
      if (index == null || index >= row.length) return '';
      final value = row[index];
      if (value.length > maxCellCharacters) {
        throw FormatException(
          'The $key field is longer than 1,000 characters.',
        );
      }
      return value;
    }

    final result = <Map<String, Object?>>[];
    for (final row in dataRows) {
      if (row.length != rawHeaders.length) {
        throw const FormatException(
          'CSV row has a different number of columns.',
        );
      }
      final title = valueAt(row, 'title').trim();
      if (title.isEmpty ||
          title.length > 120 ||
          title.contains(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'))) {
        throw const FormatException(
          'Each task title must contain 1–120 printable characters.',
        );
      }
      final doneText = valueAt(row, 'done').trim().toLowerCase();
      final bool done;
      if (doneText.isEmpty || doneText == 'false' || doneText == '0') {
        done = false;
      } else if (doneText == 'true' || doneText == '1') {
        done = true;
      } else {
        throw const FormatException(
          'The done column must be true, false, 1, or 0.',
        );
      }
      result.add({
        'title': title,
        'done': done,
        'imported_inactive_schedule_metadata': {
          'due_date': valueAt(row, 'due_date'),
          'reminder': valueAt(row, 'reminder'),
          'repeat': valueAt(row, 'repeat'),
          'active': false,
        },
      });
    }
    return result;
  }

  static List<List<String>> _decode(String text) {
    final rows = <List<String>>[];
    var row = <String>[];
    var cell = StringBuffer();
    var quoted = false;
    var afterQuote = false;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (quoted) {
        if (char == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            quoted = false;
            afterQuote = true;
          }
        } else {
          cell.write(char);
        }
        continue;
      }
      if (afterQuote &&
          char != ',' &&
          char != '\r' &&
          char != '\n' &&
          char != ' ' &&
          char != '\t') {
        throw const FormatException(
          'Unexpected character after a quoted CSV field.',
        );
      }
      if (char == '"') {
        if (cell.isNotEmpty || afterQuote) {
          throw const FormatException('Quote found in an unquoted CSV field.');
        }
        quoted = true;
      } else if (char == ',') {
        row.add(cell.toString());
        cell = StringBuffer();
        afterQuote = false;
      } else if (char == '\r' || char == '\n') {
        if (char == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        row.add(cell.toString());
        rows.add(row);
        row = <String>[];
        cell = StringBuffer();
        afterQuote = false;
      } else {
        cell.write(char);
      }
    }
    if (quoted) {
      throw const FormatException('CSV has an unterminated quoted field.');
    }
    if (row.isNotEmpty || cell.isNotEmpty || afterQuote) {
      row.add(cell.toString());
      rows.add(row);
    }
    while (rows.isNotEmpty && rows.last.every((value) => value.isEmpty)) {
      rows.removeLast();
    }
    return rows;
  }

  static String _encodeCell(String raw) {
    final leading = raw.trimLeft();
    final dangerous =
        leading.isNotEmpty &&
        (leading.startsWith('=') ||
            leading.startsWith('+') ||
            leading.startsWith('-') ||
            leading.startsWith('@') ||
            raw.startsWith('\t') ||
            raw.startsWith('\r'));
    final safe = dangerous ? "'$raw" : raw;
    if (safe.contains(',') ||
        safe.contains('"') ||
        safe.contains('\r') ||
        safe.contains('\n')) {
      return '"${safe.replaceAll('"', '""')}"';
    }
    return safe;
  }
}

/// Stable display-only sort helpers; they never modify the saved task order.
List<Map<String, dynamic>> sortLocalTasks(
  List<Map<String, dynamic>> tasks,
  String mode,
) {
  final indexed = List.generate(tasks.length, (index) => (index, tasks[index]));
  indexed.sort((left, right) {
    final a = left.$2;
    final b = right.$2;
    final order = switch (mode) {
      'title' => (a['title']?.toString() ?? '').toLowerCase().compareTo(
        (b['title']?.toString() ?? '').toLowerCase(),
      ),
      'open' => (a['done'] == true ? 1 : 0).compareTo(
        b['done'] == true ? 1 : 0,
      ),
      _ => 0,
    };
    return order == 0 ? left.$1.compareTo(right.$1) : order;
  });
  return indexed.map((entry) => entry.$2).toList(growable: false);
}
