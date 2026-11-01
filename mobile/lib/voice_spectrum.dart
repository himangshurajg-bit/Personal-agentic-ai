import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

const List<double> voiceSpectrumCenterFrequenciesHz = [
  120,
  220,
  400,
  700,
  1100,
  1700,
  2600,
  3900,
  5700,
];

/// Measures nine logarithmically spaced audio bands from mono PCM16 little-endian.
/// This is a local Goertzel spectrum estimate, not a full FFT or speech recognizer.
List<double> voiceSpectrumBands(
  Uint8List pcm16le, {
  int sampleRate = 16000,
  int minimumSamples = 256,
}) {
  final sampleCount = pcm16le.length ~/ 2;
  if (sampleRate <= 0 || sampleCount < minimumSamples) {
    return List<double>.filled(voiceSpectrumCenterFrequenciesHz.length, 0);
  }

  final windowed = List<double>.filled(sampleCount, 0);
  var windowSum = 0.0;
  for (var i = 0; i < sampleCount; i++) {
    final raw = pcm16le[i * 2] | (pcm16le[i * 2 + 1] << 8);
    final signed = raw >= 0x8000 ? raw - 0x10000 : raw;
    final window = sampleCount == 1
        ? 1.0
        : 0.5 - 0.5 * math.cos(2 * math.pi * i / (sampleCount - 1));
    windowed[i] = signed / 32768.0 * window;
    windowSum += window;
  }
  if (windowSum == 0) {
    return List<double>.filled(voiceSpectrumCenterFrequenciesHz.length, 0);
  }

  return List<double>.unmodifiable(
    voiceSpectrumCenterFrequenciesHz.map((frequency) {
      if (frequency >= sampleRate / 2) return 0.0;
      final coefficient = 2 * math.cos(2 * math.pi * frequency / sampleRate);
      var previous = 0.0;
      var beforePrevious = 0.0;
      for (final sample in windowed) {
        final current = sample + coefficient * previous - beforePrevious;
        beforePrevious = previous;
        previous = current;
      }
      final power = math.max(
        0.0,
        previous * previous +
            beforePrevious * beforePrevious -
            coefficient * previous * beforePrevious,
      );
      final magnitude = math.sqrt(power) * 2 / windowSum;
      if (magnitude <= 0) return 0.0;
      final decibels = 20 * math.log(magnitude) / math.ln10;
      return ((decibels + 56) / 40).clamp(0.0, 1.0).toDouble();
    }),
  );
}

/// Compact live spectrum bars for audio already being captured with consent.
class VoiceSpectrumBars extends StatelessWidget {
  const VoiceSpectrumBars({super.key, required this.levels});

  final List<double> levels;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _VoiceSpectrumPainter(
      levels,
      Theme.of(context).colorScheme.primary,
    ),
  );
}

class _VoiceSpectrumPainter extends CustomPainter {
  const _VoiceSpectrumPainter(this.levels, this.color);

  final List<double> levels;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    const count = 9;
    const gap = 3.0;
    final barWidth = (size.width - gap * (count - 1)) / count;
    final paint = Paint()..color = color;
    for (var i = 0; i < count; i++) {
      final value = i < levels.length
          ? levels[i].clamp(0.0, 1.0).toDouble()
          : 0.0;
      final height = 3.0 + value * (size.height - 3.0);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          i.toDouble() * (barWidth + gap),
          (size.height - height) / 2,
          barWidth,
          height,
        ),
        const Radius.circular(3),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _VoiceSpectrumPainter oldDelegate) =>
      oldDelegate.color != color || !_sameLevels(oldDelegate.levels, levels);

  bool _sameLevels(List<double> left, List<double> right) {
    if (identical(left, right)) return true;
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }
}
