package dev.personalagent.personal_assistant

/** Bounded values for an explicit handoff to Android Clock; this does not start a timer. */
internal data class SystemClockTimerRequest(val seconds: Int, val label: String)

internal object SystemClockTimerRequestParser {
    const val MIN_SECONDS = 1
    const val MAX_SECONDS = 86_400
    const val MAX_LABEL_LENGTH = 40
    private val secondsPattern = Regex("^[0-9]{1,6}$")

    fun parse(secondsValue: Any?, rawLabel: Any?): SystemClockTimerRequest? {
        val secondsText = when (secondsValue) {
            is Int -> secondsValue.toString()
            is Long -> secondsValue.takeIf { it in Int.MIN_VALUE..Int.MAX_VALUE }?.toString()
            is String -> secondsValue.trim()
            else -> null
        } ?: return null
        if (!secondsPattern.matches(secondsText)) return null
        val seconds = secondsText.toIntOrNull() ?: return null
        if (seconds !in MIN_SECONDS..MAX_SECONDS) return null

        val label = (rawLabel as? String)?.trim() ?: return null
        if (label.length > MAX_LABEL_LENGTH || label.any(Char::isISOControl)) return null
        return SystemClockTimerRequest(seconds, label)
    }
}
