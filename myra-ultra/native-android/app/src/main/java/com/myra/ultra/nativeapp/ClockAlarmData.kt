package com.myra.ultra.nativeapp

/** A validated request passed to Android's Clock app; creating it does not set an alarm. */
internal data class ClockAlarmRequest(
    val hour: Int,
    val minute: Int,
    val label: String,
)

internal object ClockAlarmData {
    const val MAX_LABEL_LENGTH = 40
    private val clockValuePattern = Regex("^[0-9]{1,2}$")

    /** Returns null for invalid hours, minutes, or labels. Blank labels use the source app's MYRA default. */
    fun parse(hourText: String, minuteText: String, rawLabel: String): ClockAlarmRequest? {
        val hourInput = hourText.trim()
        val minuteInput = minuteText.trim()
        if (!clockValuePattern.matches(hourInput) || !clockValuePattern.matches(minuteInput)) return null
        val hour = hourInput.toIntOrNull() ?: return null
        val minute = minuteInput.toIntOrNull() ?: return null
        if (hour !in 0..23 || minute !in 0..59) return null

        val label = rawLabel.trim().ifEmpty { "MYRA" }
        if (label.length > MAX_LABEL_LENGTH || label.any(Char::isISOControl)) return null
        return ClockAlarmRequest(hour, minute, label)
    }
}
