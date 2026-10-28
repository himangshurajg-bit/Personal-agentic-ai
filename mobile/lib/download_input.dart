/// Validation for the explicit, user-started Android download handoff.
class DownloadInput {
  const DownloadInput({required this.url, required this.fileName});

  final String url;
  final String fileName;

  static DownloadInput? parse(String raw) {
    final value = raw.trim();
    if (value.isEmpty ||
        value.length > 2048 ||
        value.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      return null;
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    final rawName = uri.pathSegments.isEmpty || uri.pathSegments.last.isEmpty
        ? 'download'
        : uri.pathSegments.last;
    final sanitized = rawName
        .replaceAll(RegExp(r'[^A-Za-z0-9._() -]'), '_')
        .trim()
        .replaceAll(RegExp(r'^\.+|\.+$'), '');
    final safe = sanitized.length > 120
        ? sanitized.substring(0, 120)
        : sanitized;
    return DownloadInput(
      url: uri.toString(),
      fileName: safe.isEmpty ? 'download' : safe,
    );
  }
}
