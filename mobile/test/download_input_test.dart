import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/download_input.dart';

void main() {
  group('DownloadInput', () {
    test('accepts one HTTP(S) URL and derives a bounded safe filename', () {
      final parsed = DownloadInput.parse(
        ' https://example.com/files/report.pdf?x=1 ',
      );
      expect(parsed?.url, 'https://example.com/files/report.pdf?x=1');
      expect(parsed?.fileName, 'report.pdf');
      expect(DownloadInput.parse('http://example.com/'), isNotNull);
    });

    test('rejects non-web, hostless and credential-bearing URLs', () {
      for (final value in [
        '',
        'file:///etc/passwd',
        'javascript:alert(1)',
        'https:/missing-host',
        'https://user:pass@example.com/a',
      ]) {
        expect(DownloadInput.parse(value), isNull, reason: value);
      }
    });

    test('bounds input and sanitizes path-derived names', () {
      expect(DownloadInput.parse('https://example.com/${'a' * 2049}'), isNull);
      final parsed = DownloadInput.parse(
        'https://example.com/%3Csecret%3E.txt',
      );
      expect(parsed?.fileName, '_secret_.txt');
      expect(DownloadInput.parse('https://example.com/'), isNotNull);
      expect(DownloadInput.parse('https://example.com/')?.fileName, 'download');
    });
  });
}
