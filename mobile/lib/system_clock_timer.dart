/// Validated request for Android's system Clock timer UI.
class SystemClockTimerRequest {
  final int seconds;
  final String label;

  const SystemClockTimerRequest({required this.seconds, required this.label});
}

const int minSystemClockTimerSeconds = 1;
const int maxSystemClockTimerSeconds = 86400;
const int maxSystemClockTimerLabelLength = 40;

/// Parses a bounded whole-second duration and optional single-line label.
/// Returns null rather than guessing or clamping invalid input.
SystemClockTimerRequest? parseSystemClockTimerRequest(
  String secondsText,
  String rawLabel,
) {
  final input = secondsText.trim();
  if (!RegExp(r'^[0-9]{1,6}$').hasMatch(input)) return null;
  final seconds = int.tryParse(input);
  if (seconds == null ||
      seconds < minSystemClockTimerSeconds ||
      seconds > maxSystemClockTimerSeconds) {
    return null;
  }
  final label = rawLabel.trim();
  if (label.length > maxSystemClockTimerLabelLength ||
      label.runes.any((rune) => rune < 0x20 || rune == 0x7f)) {
    return null;
  }
  return SystemClockTimerRequest(seconds: seconds, label: label);
}
