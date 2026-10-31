package dev.personalagent.personal_assistant

/** Bounded values for an explicit handoff to Android Clock; this does not save an alarm. */
internal data class SystemClockAlarmRequest(val hour: Int, val minute: Int)

internal object SystemClockAlarmRequestParser {
    fun parse(hourValue: Any?, minuteValue: Any?): SystemClockAlarmRequest? {
        val hour = when (hourValue) {
            is Int -> hourValue
            else -> return null
        }
        val minute = when (minuteValue) {
            is Int -> minuteValue
            else -> return null
        }
        if (hour !in 0..23 || minute !in 0..59) return null
        return SystemClockAlarmRequest(hour, minute)
    }
}
