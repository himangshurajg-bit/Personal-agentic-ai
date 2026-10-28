import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/clipboard_text_preview.dart';

void main() {
  test('rejects missing and empty clipboard text', () {
    expect(ClipboardTextPreview.fromText(null), isNull);
    expect(ClipboardTextPreview.fromText(''), isNull);
  });

  test('keeps short text exactly and marks it untruncated', () {
    final preview = ClipboardTextPreview.fromText('  sample\n')!;
    expect(preview.text, '  sample\n');
    expect(preview.truncated, isFalse);
  });

  test('caps long text at 4,000 UTF-16 units', () {
    final preview = ClipboardTextPreview.fromText('x' * 4003)!;
    expect(preview.text.length, 4000);
    expect(preview.truncated, isTrue);
  });

  test('does not split a supplementary character at the cap', () {
    final source = '${'a' * 3999}😀tail';
    final preview = ClipboardTextPreview.fromText(source)!;
    expect(preview.text, 'a' * 3999);
    expect(preview.truncated, isTrue);
  });
}
