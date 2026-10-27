import 'dart:convert';

const maxTextToolsInputBytes = 32 * 1024;
const maxTextToolsOutputBytes = 64 * 1024;
const maxTextToolsJsonDepth = 32;

enum TextToolOperation {
  base64Encode('Base64 encode'),
  base64Decode('Base64 decode'),
  formEncode('URL form encode'),
  formDecode('URL form decode'),
  jsonPretty('JSON pretty-print'),
  jsonMinify('JSON minify');

  const TextToolOperation(this.label);
  final String label;
}

/// Bounded, local-only text transformations used by the Text tools screen.
class TextTools {
  const TextTools._();

  static String transform(String input, TextToolOperation operation) {
    _checkBytes(input, maxTextToolsInputBytes, 'Input');
    final output = switch (operation) {
      TextToolOperation.base64Encode => base64Encode(utf8.encode(input)),
      TextToolOperation.base64Decode => utf8.decode(base64Decode(input)),
      TextToolOperation.formEncode => Uri.encodeQueryComponent(input),
      TextToolOperation.formDecode => _decodeForm(input),
      TextToolOperation.jsonPretty => _formatJson(input, pretty: true),
      TextToolOperation.jsonMinify => _formatJson(input, pretty: false),
    };
    _checkBytes(output, maxTextToolsOutputBytes, 'Output');
    return output;
  }

  static String _decodeForm(String input) {
    try {
      return Uri.decodeQueryComponent(input);
    } on ArgumentError {
      throw const FormatException('Input contains invalid URL form encoding.');
    }
  }

  static String _formatJson(String input, {required bool pretty}) {
    _checkJsonDepth(input);
    final value = jsonDecode(input);
    if (value is! List && value is! Map) {
      throw const FormatException('JSON must be an object or array.');
    }
    return pretty
        ? JsonEncoder.withIndent('  ').convert(value)
        : jsonEncode(value);
  }

  static void _checkBytes(String value, int limit, String label) {
    if (utf8.encode(value).length > limit) {
      throw FormatException('$label exceeds $limit UTF-8 bytes.');
    }
  }

  /// Counts structural nesting outside JSON strings before re-encoding.
  static void _checkJsonDepth(String input) {
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (final rune in input.runes) {
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (rune == 0x5c) {
          escaped = true;
        } else if (rune == 0x22) {
          inString = false;
        }
        continue;
      }
      if (rune == 0x22) {
        inString = true;
      } else if (rune == 0x7b || rune == 0x5b) {
        depth++;
        if (depth > maxTextToolsJsonDepth) {
          throw FormatException(
            'JSON nesting exceeds $maxTextToolsJsonDepth levels.',
          );
        }
      } else if (rune == 0x7d || rune == 0x5d) {
        if (depth > 0) depth--;
      }
    }
  }
}
