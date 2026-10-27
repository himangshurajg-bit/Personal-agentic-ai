package com.myra.ultra.nativeapp

/** A validated duration passed to Android's Clock app; creating the request does not start a timer. */
internal data class ClockTimerRequest(
    val seconds: Int,
    val label: String,
) {
    val displayDuration: String get() = when {
        seconds % 3600 == 0 -> "${seconds / 3600} ${if (seconds / 3600 == 1) "hour" else "hours"}"
        seconds % 60 == 0 -> "${seconds / 60} ${if (seconds / 60 == 1) "minute" else "minutes"}"
        else -> "$seconds ${if (seconds == 1) "second" else "seconds"}"
    }
}

internal object ClockTimerData {
    const val MIN_SECONDS = 1
    const val MAX_SECONDS = 86_400
    const val MAX_LABEL_LENGTH = 40
    private val secondsPattern = Regex("^[0-9]{1,6}$")

    /** Returns null for invalid duration or label. Blank labels use the source app's MYRA default. */
    fun parse(secondsText: String, rawLabel: String): ClockTimerRequest? {
        val input = secondsText.trim()
        if (!secondsPattern.matches(input)) return null
        val seconds = input.toIntOrNull() ?: return null
        if (seconds !in MIN_SECONDS..MAX_SECONDS) return null

        val label = rawLabel.trim().ifEmpty { "MYRA" }
        if (label.length > MAX_LABEL_LENGTH || label.any(Char::isISOControl)) return null
        return ClockTimerRequest(seconds, label)
    }
}
