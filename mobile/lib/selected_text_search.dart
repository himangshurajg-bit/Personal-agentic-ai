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
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty || maxResults <= 0) return const [];

  final results = <SelectedTextMatch>[];
  final lines = document.split('\n');
  for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
    final line = lines[lineIndex];
    final searchable = line.toLowerCase();
    var offset = 0;
    while (offset <= searchable.length - needle.length) {
      final matchAt = searchable.indexOf(needle, offset);
      if (matchAt < 0) break;
      results.add(
        SelectedTextMatch(
          lineNumber: lineIndex + 1,
          snippet: _snippet(line, matchAt, needle.length),
        ),
      );
      if (results.length >= maxResults) return results;
      offset = matchAt + needle.length;
    }
  }
  return results;
}

String _snippet(String line, int matchAt, int queryLength) {
  const context = 90;
  final start = (matchAt - context).clamp(0, line.length);
  final end = (matchAt + queryLength + context).clamp(0, line.length);
  final prefix = start > 0 ? '…' : '';
  final suffix = end < line.length ? '…' : '';
  return '$prefix${line.substring(start, end)}$suffix';
}
