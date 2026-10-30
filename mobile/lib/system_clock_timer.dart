/// Validated request for Android's system Clock timer UI.
class SystemClockTimerRequest {
  final int seconds;
  final String label;

  const SystemClockTimerRequest({required this.seconds, required this.label});
}

const int minSystemClockTimerSeconds = 1;
const int maxSystemClockTimerSeconds = 86400;
const int maxSystemClockTimerLabelLength = 40;

/// Recognizes only a direct, one-shot spoken timer command with one exact duration.
/// This is a local shortcut; it never infers intent from an assistant reply.
SystemClockTimerRequest? parseExplicitSpokenTimerCommand(String utterance) {
  final text = utterance.trim();
  if (text.isEmpty || text.length > 160) return null;
  final directRequest = RegExp(
    r'^(?:please\s+)?(?:set|start|create)\s+(?:a\s+)?timer\s+(?:for|of)\b',
    caseSensitive: false,
  );
  if (!directRequest.hasMatch(text)) return null;
  if (RegExp(
    r"\b(?:don't|do not|never|cancel|not|if|when|tomorrow|daily|every|later|next|schedule|remind|alarm|repeat|repeating)\b",
    caseSensitive: false,
  ).hasMatch(text)) {
    return null;
  }
  final durations = RegExp(
    r'(?<![0-9.\-+])([0-9]{1,5})\s*(seconds?|secs?|minutes?|mins?|hours?|hrs?)(?![a-z])',
    caseSensitive: false,
  ).allMatches(text).toList();
  if (durations.length != 1) return null;
  final match = durations.single;
  final tail = text.substring(match.end);
  if (!RegExp(r'^[\s,;:]*(?:please)?[.!?]?$').hasMatch(tail)) return null;
  final amount = int.tryParse(match.group(1)!);
  if (amount == null) return null;
  final unit = match.group(2)!.toLowerCase();
  final multiplier = unit.startsWith('sec')
      ? 1
      : unit.startsWith('min')
      ? 60
      : 3600;
  final seconds = amount * multiplier;
  if (seconds < minSystemClockTimerSeconds ||
      seconds > maxSystemClockTimerSeconds) {
    return null;
  }
  return SystemClockTimerRequest(seconds: seconds, label: 'Personal AI');
}

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
