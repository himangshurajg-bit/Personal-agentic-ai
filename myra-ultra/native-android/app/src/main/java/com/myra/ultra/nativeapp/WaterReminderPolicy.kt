package com.myra.ultra.nativeapp

import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/** Pure local-time and target checks for the optional reminder tied to a user-selected water target. */
internal object WaterReminderPolicy {
    private val timePattern = Regex("\\d{2}:\\d{2}")

    fun parseMinutesSinceMidnight(input: String): Int? {
        val value = input.trim()
        if (!timePattern.matches(value)) return null
        val hour = value.substring(0, 2).toIntOrNull() ?: return null
        val minute = value.substring(3, 5).toIntOrNull() ?: return null
        if (hour !in 0..23 || minute !in 0..59) return null
        return hour * 60 + minute
    }

    /** Return the next local wall-clock occurrence; a missed time rolls to the next calendar day. */
    fun nextOccurrence(nowMillis: Long, minutesSinceMidnight: Int, timeZone: TimeZone = TimeZone.getDefault()): Long? {
        if (minutesSinceMidnight !in 0 until 24 * 60) return null
        val calendar = Calendar.getInstance(timeZone).apply {
            timeInMillis = nowMillis
            set(Calendar.HOUR_OF_DAY, minutesSinceMidnight / 60)
            set(Calendar.MINUTE, minutesSinceMidnight % 60)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= nowMillis) add(Calendar.DAY_OF_MONTH, 1)
        }
        return calendar.timeInMillis
    }

    fun localDateKey(timeMillis: Long, timeZone: TimeZone = TimeZone.getDefault()): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).apply { this.timeZone = timeZone }.format(Date(timeMillis))

    fun shouldNotify(enabled: Boolean, targetMilliliters: Int, totalMilliliters: Long): Boolean =
        enabled && targetMilliliters in WaterTarget.MIN_MILLILITERS..WaterTarget.MAX_MILLILITERS &&
            totalMilliliters.coerceAtLeast(0) < targetMilliliters
}
