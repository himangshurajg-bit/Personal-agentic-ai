/// A bounded match within one user-selected, locally readable text document.
class SelectedTextMatch {
  final int lineNumber;
  final String snippet;

  const SelectedTextMatch({required this.lineNumber, required this.snippet});
}

/// Searches only the text already held by the selected-file preview.
///
/// The caller owns the document picker and supplies the exact selected text.
/// This helper has no storage, indexing, network, or AI dependencies. Results
/// are capped so repeated/common characters cannot create an unbounded list.
List<SelectedTextMatch> searchSelectedText(
  String document,
  String query, {
  int maxResults = 100,
}) {
  final needle = _caseFold(query.trim());
  if (needle.isEmpty || maxResults <= 0) return const [];

  final results = <SelectedTextMatch>[];
  final lines = document.split('\n');
  for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
    final line = lines[lineIndex];
    final searchable = _lowercaseWithOffsets(line);
    var offset = 0;
    while (offset <= searchable.text.length - needle.length) {
      final matchAt = searchable.text.indexOf(needle, offset);
      if (matchAt < 0) break;
      final matchEnd = matchAt + needle.length;
      results.add(
        SelectedTextMatch(
          lineNumber: lineIndex + 1,
          snippet: _snippet(
            line,
            searchable.sourceStarts[matchAt],
            searchable.sourceEnds[matchEnd - 1],
          ),
        ),
      );
      if (results.length >= maxResults) return results;
      offset = matchEnd;
    }
  }
  return results;
}

String _caseFold(String source) {
  final folded = StringBuffer();
  for (final rune in source.runes) {
    folded.write(_foldRune(rune));
  }
  return folded.toString();
}

String _foldRune(int rune) {
  // Dart's lowercase mapping for U+0130 omits its combining dot; preserve the
  // Unicode lowercase expansion so text and query fold to the same sequence.
  if (rune == 0x0130) return 'i\u0307';
  return String.fromCharCode(rune).toLowerCase();
}

class _LowercaseOffsets {
  final String text;
  final List<int> sourceStarts;
  final List<int> sourceEnds;

  const _LowercaseOffsets(this.text, this.sourceStarts, this.sourceEnds);
}

_LowercaseOffsets _lowercaseWithOffsets(String source) {
  final lowered = _caseFold(source);
  final starts = <int>[];
  final ends = <int>[];
  var sourceOffset = 0;
  for (final rune in source.runes) {
    final original = String.fromCharCode(rune);
    final sourceEnd = sourceOffset + original.length;
    // Some Unicode lowercase mappings expand to multiple UTF-16 units. Map
    // every output unit back to the complete source rune for correct snippets.
    final mapped = _foldRune(rune);
    for (var i = 0; i < mapped.length; i++) {
      starts.add(sourceOffset);
      ends.add(sourceEnd);
    }
    sourceOffset = sourceEnd;
  }
  return _LowercaseOffsets(lowered, starts, ends);
}

String _snippet(String line, int matchStart, int matchEnd) {
  const context = 90;
  var start = (matchStart - context).clamp(0, line.length);
  var end = (matchEnd + context).clamp(0, line.length);
  if (start > 0 &&
      start < line.length &&
      _isLowSurrogate(line.codeUnitAt(start)) &&
      _isHighSurrogate(line.codeUnitAt(start - 1))) {
    start--;
  }
  if (end > 0 &&
      end < line.length &&
      _isHighSurrogate(line.codeUnitAt(end - 1)) &&
      _isLowSurrogate(line.codeUnitAt(end))) {
    end++;
  }
  final prefix = start > 0 ? '…' : '';
  final suffix = end < line.length ? '…' : '';
  return '$prefix${line.substring(start, end)}$suffix';
}

bool _isHighSurrogate(int value) => value >= 0xD800 && value <= 0xDBFF;
bool _isLowSurrogate(int value) => value >= 0xDC00 && value <= 0xDFFF;
