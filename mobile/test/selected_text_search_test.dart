import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/selected_text_search.dart';

void main() {
  group('selected text search', () {
    test('matches case-insensitively and reports one-based line numbers', () {
      final matches = searchSelectedText(
        'Newton\nSecond LAW\nnewtonian law',
        'LAW',
      );
      expect(matches.map((match) => match.lineNumber), [2, 3]);
      expect(matches.first.snippet, 'Second LAW');
    });

    test('finds repeated phrases but does not overlap matches', () {
      final matches = searchSelectedText('cat catcat', 'cat');
      expect(matches.map((match) => match.lineNumber), [1, 1, 1]);
    });

    test('empty queries and nonpositive limits return no results', () {
      expect(searchSelectedText('some text', '  '), isEmpty);
      expect(searchSelectedText('some text', 'text', maxResults: 0), isEmpty);
    });

    test('caps common-character matches and shortens long-line snippets', () {
      expect(searchSelectedText('aaaaaa', 'a', maxResults: 3), hasLength(3));
      final longLine = '${'x' * 200}needle${'y' * 200}';
      final match = searchSelectedText(longLine, 'needle').single;
      expect(match.snippet.length, lessThan(longLine.length));
      expect(match.snippet, startsWith('…'));
      expect(match.snippet, endsWith('…'));
      expect(match.snippet, contains('needle'));
    });

    test('searches within exact selected text only', () {
      expect(searchSelectedText('only this document', 'other'), isEmpty);
      expect(
        searchSelectedText('selected document', 'document').single.lineNumber,
        1,
      );
    });

    test('maps Unicode lowercase expansions back to the original snippet', () {
      final matches = searchSelectedText('İstanbul is beautiful', 'i\u0307');
      expect(matches, hasLength(1));
      expect(matches.single.lineNumber, 1);
      expect(matches.single.snippet, 'İstanbul is beautiful');
    });
  });
}
