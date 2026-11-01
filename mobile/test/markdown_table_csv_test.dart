import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/markdown_table_csv.dart';

void main() {
  group('Markdown table CSV export', () {
    test('converts a bounded pipe table with Unicode and quoted cells', () {
      final tables = parseMarkdownCsvTables('''
| Item | Notes | Count |
|:---|:---:|---:|
| Tea | Assam, fresh | 2 |
| "Cup" | অসমীয়া 😀 | 3 |
''');
      expect(tables, hasLength(1));
      expect(
        tables.single.toCsv(),
        'Item,Notes,Count\r\nTea,"Assam, fresh",2\r\n"""Cup""",অসমীয়া 😀,3\r\n',
      );
    });

    test(
      'preserves escaped pipe characters and ignores fenced code examples',
      () {
        final tables = parseMarkdownCsvTables('''
```markdown
| Fake | table |
| --- | --- |
| no | parse |
```

| Real | Value |
| --- | --- |
| A\\|B | C |
''');
        expect(tables, hasLength(1));
        expect(tables.single.toCsv(), 'Real,Value\r\nA|B,C\r\n');
      },
    );

    test(
      'prefixes spreadsheet formulas as text without changing plain numbers',
      () {
        final tables = parseMarkdownCsvTables('''
| Value |
| --- |
| =1+1 |
|  @SUM(A1:A2) |
| -12.5 |
| -1+1 |
''');
        expect(
          tables.single.toCsv(),
          "Value\r\n'=1+1\r\n'@SUM(A1:A2)\r\n-12.5\r\n'-1+1\r\n",
        );
      },
    );

    test('skips malformed tables and caps oversized input', () {
      expect(
        parseMarkdownCsvTables('''
| A | B |
| --- |
| 1 | 2 |
'''),
        isEmpty,
      );
      expect(
        parseMarkdownCsvTables('x' * (maxMarkdownCsvSourceCharacters + 1)),
        isEmpty,
      );
    });

    test('caps row count and cell size', () {
      final manyRows = StringBuffer('| A | B |\n| --- | --- |\n');
      for (var i = 0; i < maxMarkdownCsvRows + 2; i++) {
        manyRows.writeln('| $i | value |');
      }
      final parsed = parseMarkdownCsvTables(manyRows.toString());
      expect(parsed, hasLength(1));
      expect(parsed.single.rows, hasLength(maxMarkdownCsvRows + 1));

      final largeCell = 'x' * (maxMarkdownCsvCellCharacters + 1);
      expect(parseMarkdownCsvTables('| A |\n| --- |\n| $largeCell |'), isEmpty);
    });
  });
}
