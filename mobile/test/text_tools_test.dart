import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/text_tools.dart';

void main() {
  group('TextTools', () {
    test('Base64 round-trips UTF-8 text', () {
      const text = 'Assamese: অসমীয়া — café';
      final encoded = TextTools.transform(text, TextToolOperation.base64Encode);
      expect(
        TextTools.transform(encoded, TextToolOperation.base64Decode),
        text,
      );
    });

    test('URL form encoding round-trips reserved characters and spaces', () {
      const text = 'a + b & c=1/2';
      final encoded = TextTools.transform(text, TextToolOperation.formEncode);
      expect(encoded, contains('+'));
      expect(TextTools.transform(encoded, TextToolOperation.formDecode), text);
    });

    test('formats and minifies only JSON objects or arrays', () {
      const input = '{"x":[1,{"y":true}],"s":"{[not structure]"}';
      final pretty = TextTools.transform(input, TextToolOperation.jsonPretty);
      expect(pretty, contains('\n'));
      final compact = TextTools.transform(pretty, TextToolOperation.jsonMinify);
      expect(jsonDecode(compact), jsonDecode(input));
      expect(compact, isNot(contains('\n')));
      expect(
        () => TextTools.transform('true', TextToolOperation.jsonPretty),
        throwsFormatException,
      );
    });

    test('rejects invalid UTF-8 base64 and malformed form escapes', () {
      expect(
        () => TextTools.transform(
          '%%%not-base64',
          TextToolOperation.base64Decode,
        ),
        throwsFormatException,
      );
      expect(
        () => TextTools.transform('%zz', TextToolOperation.formDecode),
        throwsFormatException,
      );
      expect(
        () => TextTools.transform(
          base64Encode([0xff]),
          TextToolOperation.base64Decode,
        ),
        throwsFormatException,
      );
    });

    test('enforces byte and JSON nesting limits', () {
      expect(
        () => TextTools.transform(
          'é' * (maxTextToolsInputBytes ~/ 2 + 1),
          TextToolOperation.formEncode,
        ),
        throwsFormatException,
      );
      final deepJson =
          '${'[' * (maxTextToolsJsonDepth + 1)}0${']' * (maxTextToolsJsonDepth + 1)}';
      expect(
        () => TextTools.transform(deepJson, TextToolOperation.jsonPretty),
        throwsFormatException,
      );
      expect(
        () => TextTools.transform(
          'x' * (maxTextToolsOutputBytes + 1),
          TextToolOperation.base64Encode,
        ),
        throwsFormatException,
      );
    });
  });
}
