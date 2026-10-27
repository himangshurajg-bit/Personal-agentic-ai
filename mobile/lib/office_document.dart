import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

const maxDocxBytes = 12 * 1024 * 1024;
const maxDocxEntries = 2048;
const maxDocxExpandedBytes = 64 * 1024 * 1024;
const maxDocxXmlBytes = 8 * 1024 * 1024;
const maxExtractedDocxChars = 60000;

class ExtractedOfficeText {
  final String text;
  final bool truncated;

  const ExtractedOfficeText(this.text, {this.truncated = false});
}

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
