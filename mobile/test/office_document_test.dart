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
  group('DOCX text generation', () {
    test(
      'creates a valid local OOXML package and preserves Unicode and text',
      () {
        final source = """A&B <word> "quoted" 'ok'
অসমীয়া 😀
Next""";
        final bytes = createDocxFromText(
          title: 'Personal AI response',
          text: source,
        );
        final archive = ZipDecoder().decodeBytes(bytes);
        expect(archive.findFile('[Content_Types].xml'), isNotNull);
        expect(archive.findFile('_rels/.rels'), isNotNull);
        final document = archive.findFile('word/document.xml');
        expect(document, isNotNull);
        final xml = utf8.decode(List<int>.from(document!.content as List<int>));
        expect(xml, contains('A&amp;B &lt;word&gt;'));
        expect(extractDocxText(bytes).text, 'Personal AI response\n$source');
        expect(bytes.length, lessThanOrEqualTo(maxGeneratedDocxBytes));
      },
    );

    test('rejects empty content and invalid titles', () {
      expect(
        () => createDocxFromText(title: 'Title', text: '  \n  '),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => createDocxFromText(title: '', text: 'Answer'),
        throwsA(isA<FormatException>()),
      );
    });

    test('removes XML-invalid control characters', () {
      final result = extractDocxText(
        createDocxFromText(title: 'Title', text: 'A\u0001B'),
      );
      expect(result.text, 'Title\nAB');
    });
  });

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
