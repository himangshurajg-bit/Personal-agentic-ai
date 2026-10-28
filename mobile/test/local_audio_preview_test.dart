import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/local_audio_preview.dart';

void main() {
  group('audioTimeLabel', () {
    test('formats minutes and seconds', () {
      expect(audioTimeLabel(const Duration(seconds: 0)), '0:00');
      expect(audioTimeLabel(const Duration(seconds: 65)), '1:05');
    });

    test('keeps long tracks in total minutes', () {
      expect(audioTimeLabel(const Duration(hours: 1, seconds: 2)), '60:02');
    });

    test('clamps a negative duration to zero', () {
      expect(audioTimeLabel(const Duration(seconds: -1)), '0:00');
    });
  });
}
