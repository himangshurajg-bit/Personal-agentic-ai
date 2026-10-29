class ClipboardTextPreview {
  static const maxCodeUnits = 4000;

  final String text;
  final bool truncated;

  const ClipboardTextPreview(this.text, this.truncated);

  static ClipboardTextPreview? fromText(String? value) {
    if (value == null || value.isEmpty) return null;
    var end = value.length < maxCodeUnits ? value.length : maxCodeUnits;
    if (end < value.length && end > 0) {
      final before = value.codeUnitAt(end - 1);
      final after = value.codeUnitAt(end);
      final endsHighSurrogate = before >= 0xD800 && before <= 0xDBFF;
      final startsLowSurrogate = after >= 0xDC00 && after <= 0xDFFF;
      if (endsHighSurrogate && startsLowSurrogate) end--;
    }
    return ClipboardTextPreview(value.substring(0, end), value.length > end);
  }
}
