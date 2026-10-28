import 'download_input.dart';

/// Matches only an unambiguous, direct spoken download command with one URL.
///
/// This intentionally does not interpret free-form requests or infer URLs.
class SpokenDownloadCommand {
  static final RegExp _command = RegExp(
    r'^\s*(?:please\s+)?download\s+(?:this\s+file\s+)?(https?://\S+)\s*$',
    caseSensitive: false,
  );

  static DownloadInput? parse(String utterance) {
    final match = _command.firstMatch(utterance);
    if (match == null) return null;
    return DownloadInput.parse(match.group(1)!);
  }
}
