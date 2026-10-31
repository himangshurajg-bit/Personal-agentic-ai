import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/voice_spectrum.dart';

Uint8List _tone(int frequency, {int samples = 2048, int sampleRate = 16000}) {
  final bytes = ByteData(samples * 2);
  for (var i = 0; i < samples; i++) {
    final value = (12000 * math.sin(2 * math.pi * frequency * i / sampleRate))
        .round();
    bytes.setInt16(i * 2, value, Endian.little);
  }
  return bytes.buffer.asUint8List();
}

void main() {
  test('silence and incomplete PCM produce quiet bands', () {
    expect(voiceSpectrumBands(Uint8List(2048)), everyElement(0));
    expect(voiceSpectrumBands(Uint8List(100)), everyElement(0));
    expect(voiceSpectrumBands(Uint8List(2049)), everyElement(0));
  });

  test('a tone raises its matching speech-frequency band', () {
    final bands = voiceSpectrumBands(_tone(1100));
    expect(bands, hasLength(9));
    expect(bands[4], greaterThan(0.8));
    expect(bands[4], greaterThan(bands[3]));
    expect(bands[4], greaterThan(bands[5]));
  });

  test('invalid sample rates return quiet bands', () {
    expect(voiceSpectrumBands(_tone(700), sampleRate: 0), everyElement(0));
  });
}
