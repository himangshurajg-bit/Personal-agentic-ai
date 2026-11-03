/// Splits cumulative model text into speech-sized chunks without repeating deltas.
/// Complete sentences are emitted immediately; long unpunctuated output is cut at
/// a nearby word boundary so local TTS can start before the whole reply arrives.
class LiveConversationSpeechBuffer {
  String _observed = '';
  String _pending = '';

  void reset() {
    _observed = '';
    _pending = '';
  }

  List<String> add(String cumulativeText, {bool flush = false}) {
    if (cumulativeText.startsWith(_observed)) {
      _pending += cumulativeText.substring(_observed.length);
      _observed = cumulativeText;
    } else if (_observed.isEmpty || flush) {
      // A final answer is authoritative if a provider revised its partial text.
      _pending = cumulativeText;
      _observed = cumulativeText;
    } else {
      // Streaming providers normally append. Ignore a revised snapshot rather
      // than speaking the same prefix twice; the final snapshot is reconciled.
      return const [];
    }

    final chunks = <String>[];
    while (_pending.isNotEmpty) {
      final boundary = _sentenceBoundary(_pending);
      if (boundary != null) {
        _emitPrefix(boundary, chunks);
        continue;
      }
      if (_pending.length >= 170) {
        final cut = _wordBoundary(_pending, 150);
        if (cut != null) {
          _emitPrefix(cut, chunks);
          continue;
        }
      }
      break;
    }
    if (flush && _pending.trim().isNotEmpty) {
      chunks.add(_plainSpeech(_pending));
      _pending = '';
    }
    return chunks.where((chunk) => chunk.isNotEmpty).toList();
  }

  int? _sentenceBoundary(String text) {
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (char == '\n') return i + 1;
      if ('.!?।'.contains(char) &&
          (i + 1 == text.length || RegExp(r'\s').hasMatch(text[i + 1]))) {
        return i + 1;
      }
    }
    return null;
  }

  int? _wordBoundary(String text, int preferred) {
    final lower = text.lastIndexOf(' ', preferred);
    if (lower >= 90) return lower;
    final upper = text.indexOf(' ', preferred);
    if (upper >= 0 && upper <= 170) return upper;
    return null;
  }

  void _emitPrefix(int end, List<String> chunks) {
    final value = _plainSpeech(_pending.substring(0, end));
    if (value.isNotEmpty) chunks.add(value);
    _pending = _pending.substring(end).trimLeft();
  }

  String _plainSpeech(String text) {
    final withoutCode = text.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');
    final withLinkLabels = withoutCode.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\([^)]*\)'),
      (match) => match.group(1) ?? '',
    );
    final withoutListMarkers = withLinkLabels
        .split('\n')
        .map((line) {
          final trimmed = line.trimLeft();
          for (final marker in const ['- ', '* ', '+ ']) {
            if (trimmed.startsWith(marker)) return trimmed.substring(2);
          }
          return line;
        })
        .join(' ');
    return withoutListMarkers
        .replaceAll(RegExp(r'[`*_#>|]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
