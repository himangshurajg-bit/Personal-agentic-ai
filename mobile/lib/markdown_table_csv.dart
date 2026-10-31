/// Local, bounded conversion of Markdown pipe tables to spreadsheet CSV.
///
/// This parser only recognizes simple pipe tables and never executes content.
class MarkdownCsvTable {
  final List<List<String>> rows;

  MarkdownCsvTable(List<List<String>> rows)
    : rows = List.unmodifiable(
        rows.map((row) => List<String>.unmodifiable(row)),
      );

  String toCsv() {
    final output = rows
        .map((row) => row.map(_encodeCsvCell).join(','))
        .join('\r\n');
    final csv = '$output\r\n';
    if (csv.length > maxMarkdownCsvOutputCharacters) {
      throw const FormatException('The table is too large to export as CSV.');
    }
    return csv;
  }
}

const maxMarkdownCsvSourceCharacters = 60000;
const maxMarkdownCsvTables = 10;
const maxMarkdownCsvRows = 100;
const maxMarkdownCsvColumns = 20;
const maxMarkdownCsvCellCharacters = 2000;
const maxMarkdownCsvOutputCharacters = 100000;

/// Finds bounded Markdown pipe tables outside fenced code and returns their
/// literal cell text. Does not infer or repair malformed tables.
List<MarkdownCsvTable> parseMarkdownCsvTables(String markdown) {
  if (markdown.length > maxMarkdownCsvSourceCharacters) return const [];
  final lines = markdown
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  final tables = <MarkdownCsvTable>[];
  String? fence;

  for (
    var i = 0;
    i < lines.length && tables.length < maxMarkdownCsvTables;
    i++
  ) {
    final line = lines[i];
    final fenceMatch = RegExp(r'^\s*(`{3,}|~{3,})').firstMatch(line);
    if (fenceMatch != null) {
      final marker = fenceMatch.group(1)!;
      if (fence == null) {
        fence = marker[0];
      } else if (marker.startsWith(fence) && marker.length >= 3) {
        fence = null;
      }
      continue;
    }
    if (fence != null || i + 1 >= lines.length || !line.contains('|')) continue;

    final header = _splitMarkdownTableRow(line);
    final separator = _splitMarkdownTableRow(lines[i + 1]);
    if (header == null ||
        separator == null ||
        header.length != separator.length ||
        header.length > maxMarkdownCsvColumns ||
        !separator.every(
          (cell) => RegExp(r'^:?-{3,}:?$').hasMatch(cell.trim()),
        ) ||
        header.any((cell) => cell.length > maxMarkdownCsvCellCharacters)) {
      continue;
    }

    final rows = <List<String>>[header];
    var next = i + 2;
    while (next < lines.length &&
        rows.length <= maxMarkdownCsvRows &&
        lines[next].contains('|')) {
      if (RegExp(r'^\s*(`{3,}|~{3,})').hasMatch(lines[next])) break;
      final cells = _splitMarkdownTableRow(lines[next]);
      if (cells == null ||
          cells.length != header.length ||
          cells.any((cell) => cell.length > maxMarkdownCsvCellCharacters)) {
        break;
      }
      rows.add(cells);
      next++;
    }
    if (rows.length > 1 && rows.length <= maxMarkdownCsvRows + 1) {
      tables.add(MarkdownCsvTable(rows));
      i = next - 1;
    }
  }
  return List.unmodifiable(tables);
}

List<String>? _splitMarkdownTableRow(String line) {
  final cells = <String>[];
  final cell = StringBuffer();
  for (var i = 0; i < line.length; i++) {
    final char = line[i];
    if (char == '\\' && i + 1 < line.length && line[i + 1] == '|') {
      cell.write('|');
      i++;
    } else if (char == '|') {
      cells.add(cell.toString().trim());
      cell.clear();
    } else {
      cell.write(char);
    }
  }
  cells.add(cell.toString().trim());
  if (line.trimLeft().startsWith('|')) cells.removeAt(0);
  if (line.trimRight().endsWith('|') && cells.isNotEmpty) cells.removeLast();
  if (cells.isEmpty) return null;
  return cells;
}

String _encodeCsvCell(String source) {
  var value = source.replaceAll('\u0000', '');
  final firstNonSpace = value.trimLeft();
  final formulaLike = RegExp(r'^[=+\-@\t\r]').hasMatch(firstNonSpace);
  final plainNumber = RegExp(
    r'^\s*[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?\s*$',
  ).hasMatch(value);
  if (formulaLike && !plainNumber) value = "'$value";
  if (value.contains(',') ||
      value.contains('"') ||
      value.contains('\r') ||
      value.contains('\n')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}
