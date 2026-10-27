import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/office_document.dart';

Uint8List _docx(String documentXml) {
  final xmlBytes = utf8.encode(documentXml);
  final archive = Archive()
    ..addFile(ArchiveFile('word/document.xml', xmlBytes.length, xmlBytes));
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

void main() {
  group('DOCX text extraction', () {
    test(
      'extracts paragraph and table-cell text locally in document order',
      () {
        final result = extractDocxText(
          _docx('''
          <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
            <w:body>
              <w:p><w:r><w:t>Hello </w:t></w:r><w:r><w:t>world</w:t></w:r></w:p>
              <w:tbl><w:tr><w:tc><w:p><w:r><w:t>Cell text</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
            </w:body>
          </w:document>
        '''),
        );
        expect(result.text, 'Hello world\nCell text');
        expect(result.truncated, isFalse);
      },
    );

    test(
      'rejects invalid archives, missing document XML and empty documents',
      () {
        expect(
          () => extractDocxText(Uint8List.fromList([1, 2, 3])),
          throwsA(isA<FormatException>()),
        );
        final noDocument = Archive()
          ..addFile(ArchiveFile('word/styles.xml', 1, [0]));
        expect(
          () => extractDocxText(
            Uint8List.fromList(ZipEncoder().encode(noDocument)!),
          ),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => extractDocxText(
            _docx('<w:document xmlns:w="x"><w:body/></w:document>'),
          ),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test('caps output and marks truncation', () {
      final large = 'a' * (maxExtractedDocxChars + 40);
      final result = extractDocxText(
        _docx(
          '<w:document xmlns:w="x"><w:body><w:p><w:r><w:t>$large</w:t></w:r></w:p></w:body></w:document>',
        ),
      );
      expect(result.text.length, maxExtractedDocxChars);
      expect(result.truncated, isTrue);
    });
  });
}
