import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

const maxDocxBytes = 12 * 1024 * 1024;
const maxDocxEntries = 2048;
const maxDocxExpandedBytes = 64 * 1024 * 1024;
const maxDocxXmlBytes = 8 * 1024 * 1024;
const maxExtractedDocxChars = 60000;
const maxGeneratedDocxBytes = 256 * 1024;

class ExtractedOfficeText {
  final String text;
  final bool truncated;

  const ExtractedOfficeText(this.text, {this.truncated = false});
}

/// Creates a small, macro-free Word document containing user-selected text.
/// The result is a minimal OOXML package with no external relationships.
Uint8List createDocxFromText({required String title, required String text}) {
  final cleanTitle = _cleanXmlText(title.trim());
  final cleanText = _cleanXmlText(
    text.replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
  );
  if (cleanTitle.isEmpty || cleanTitle.length > 160) {
    throw const FormatException('Choose a title from 1 to 160 characters.');
  }
  if (cleanText.trim().isEmpty || cleanText.length > maxExtractedDocxChars) {
    throw const FormatException(
      'Document text must contain 1 to 60,000 characters.',
    );
  }
  final paragraphs = <String>[cleanTitle, ...cleanText.split('\n')];
  final body = paragraphs.map((paragraph) {
    final escaped = _escapeXml(paragraph);
    return '<w:p><w:r><w:t xml:space="preserve">$escaped</w:t></w:r></w:p>';
  }).join();
  final documentXml =
      """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>$body<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr></w:body>
</w:document>""";
  const contentTypes = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>""";
  const rootRelationships = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>""";
  final archive = Archive()
    ..addFile(_archiveText('[Content_Types].xml', contentTypes))
    ..addFile(_archiveText('_rels/.rels', rootRelationships))
    ..addFile(_archiveText('word/document.xml', documentXml));
  final encoded = ZipEncoder().encode(archive);
  if (encoded == null ||
      encoded.isEmpty ||
      encoded.length > maxGeneratedDocxBytes) {
    throw const FormatException(
      'The Word document exceeds the 256 KB export limit.',
    );
  }
  return Uint8List.fromList(encoded);
}

ArchiveFile _archiveText(String path, String text) {
  final bytes = utf8.encode(text);
  return ArchiveFile(path, bytes.length, bytes);
}

String _cleanXmlText(String text) => String.fromCharCodes(
  text.runes.where(
    (rune) =>
        rune == 0x09 ||
        rune == 0x0a ||
        rune == 0x0d ||
        (rune >= 0x20 && rune <= 0xd7ff) ||
        (rune >= 0xe000 && rune <= 0xfffd) ||
        (rune >= 0x10000 && rune <= 0x10ffff),
  ),
);

String _escapeXml(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

/// Extracts only ordinary paragraph text from a bounded OOXML Word document.
/// No document code, macros, embedded media or external relationships are run.
ExtractedOfficeText extractDocxText(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > maxDocxBytes) {
    throw const FormatException('The DOCX file is empty or exceeds 12 MB.');
  }
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } on Object {
    throw const FormatException('This is not a readable DOCX package.');
  }
  if (archive.files.length > maxDocxEntries) {
    throw const FormatException('The DOCX package has too many entries.');
  }
  var expandedTotal = 0;
  for (final file in archive.files) {
    if (file.size < 0 || file.size > maxDocxExpandedBytes) {
      throw const FormatException(
        'The DOCX package expands beyond safe limits.',
      );
    }
    expandedTotal += file.size;
    if (expandedTotal > maxDocxExpandedBytes) {
      throw const FormatException(
        'The DOCX package expands beyond safe limits.',
      );
    }
  }
  final document = archive.findFile('word/document.xml');
  if (document == null || !document.isFile || document.size > maxDocxXmlBytes) {
    throw const FormatException(
      'The DOCX package has no supported document text.',
    );
  }
  final List<int> xmlBytes;
  try {
    xmlBytes = List<int>.from(document.content as List<int>, growable: false);
  } on Object {
    throw const FormatException('The DOCX document text could not be read.');
  }
  if (xmlBytes.length > maxDocxXmlBytes) {
    throw const FormatException('The DOCX document text exceeds safe limits.');
  }
  final XmlDocument parsed;
  try {
    parsed = XmlDocument.parse(utf8.decode(xmlBytes, allowMalformed: false));
  } on Object {
    throw const FormatException('The DOCX document contains invalid XML.');
  }
  final paragraphs = <String>[];
  for (final paragraph in parsed.findAllElements('w:p')) {
    final text = paragraph
        .findAllElements('w:t')
        .map((node) => node.innerText)
        .join();
    if (text.isNotEmpty) paragraphs.add(text);
  }
  final fullText = paragraphs.join('\n').trim();
  if (fullText.isEmpty) {
    throw const FormatException('No readable paragraph text was found.');
  }
  if (fullText.length <= maxExtractedDocxChars) {
    return ExtractedOfficeText(fullText);
  }
  return ExtractedOfficeText(
    fullText.substring(0, maxExtractedDocxChars),
    truncated: true,
  );
}
