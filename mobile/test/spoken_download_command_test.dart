import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/spoken_download_command.dart';

void main() {
  group('SpokenDownloadCommand', () {
    test('accepts a direct download of one exact HTTP(S) URL', () {
      final request = SpokenDownloadCommand.parse(
        'Please download this file https://example.com/files/notes.pdf?rev=2',
      );

      expect(request?.url, 'https://example.com/files/notes.pdf?rev=2');
      expect(request?.fileName, 'notes.pdf');
    });

    test('rejects vague, conditional, negated, and unrelated utterances', () {
      for (final utterance in [
        'download the file',
        'if I ask later, download https://example.com/a.pdf',
        "don't download https://example.com/a.pdf",
        'open https://example.com/a.pdf',
        'download https://example.com/a.pdf and https://example.com/b.pdf',
      ]) {
        expect(SpokenDownloadCommand.parse(utterance), isNull, reason: utterance);
      }
    });

    test('requires a valid public HTTP(S) URL without embedded credentials', () {
      for (final utterance in [
        'download ftp://example.com/a.pdf',
        'download https://user:password@example.com/a.pdf',
        'download https://',
      ]) {
        expect(SpokenDownloadCommand.parse(utterance), isNull, reason: utterance);
      }
    });
  });
}
