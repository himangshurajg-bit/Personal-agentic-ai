package com.myra.ultra.nativeapp

import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.text.ParsePosition
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.UUID

internal data class MyraHabit(
    val id: String,
    val title: String,
    val completedDates: Set<String>,
)

internal object HabitTracker {
    private const val HEX = "0123456789abcdef"
    private const val MAX_TITLE_LENGTH = 80
    private const val MAX_COMPLETIONS = 3660

    fun currentDate(nowMillis: Long = System.currentTimeMillis()): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(nowMillis))

    fun isValidDate(value: String): Boolean {
        if (!Regex("\\d{4}-\\d{2}-\\d{2}").matches(value)) return false
        return try {
            val format = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply { isLenient = false }
            val position = ParsePosition(0)
            val parsed = format.parse(value, position)
            parsed != null && position.index == value.length && format.format(parsed) == value
        } catch (_: Exception) { false }
    }

    fun normalizedTitle(raw: String): String? = raw.trim().takeIf {
        it.isNotEmpty() && it.length <= MAX_TITLE_LENGTH && it.none(Char::isISOControl)
    }

    fun create(rawTitle: String, id: String = UUID.randomUUID().toString()): MyraHabit? {
        val title = normalizedTitle(rawTitle) ?: return null
        if (id.isBlank() || id.length > 128) return null
        return MyraHabit(id, title, emptySet())
    }

    fun toggle(habit: MyraHabit, date: String): MyraHabit? {
        if (!isValidDate(date)) return null
        if (date !in habit.completedDates && habit.completedDates.size >= MAX_COMPLETIONS) return null
        val next = habit.completedDates.toMutableSet()
        if (!next.add(date)) next.remove(date)
        return habit.copy(completedDates = next)
    }

    /** Returns a bounded oldest-to-newest calendar window ending on [today]. */
    fun recentDates(today: String, count: Int = 7): List<String> {
        if (!isValidDate(today) || count !in 1..31) return emptyList()
        val end = parseCalendar(today) ?: return emptyList()
        return (count - 1 downTo 0).map { daysBack ->
            (end.clone() as Calendar).apply { add(Calendar.DAY_OF_MONTH, -daysBack) }.let(::formatDate)
        }
    }

    fun recentCompletionCount(habit: MyraHabit, today: String, count: Int = 7): Int =
        recentDates(today, count).count { it in habit.completedDates }

    fun weekdayLabel(date: String, locale: Locale = Locale.getDefault()): String? {
        val calendar = parseCalendar(date) ?: return null
        return SimpleDateFormat("EE", locale).format(calendar.time)
    }

    fun currentStreak(habit: MyraHabit, today: String): Int {
        if (!isValidDate(today)) return 0
        val date = parseCalendar(today) ?: return 0
        if (today !in habit.completedDates) date.add(Calendar.DAY_OF_MONTH, -1)
        var cursor = formatDate(date)
        if (cursor !in habit.completedDates) return 0
        var streak = 0
        while (cursor in habit.completedDates && streak < MAX_COMPLETIONS) {
            streak++
            date.add(Calendar.DAY_OF_MONTH, -1)
            cursor = formatDate(date)
        }
        return streak
    }

    fun encode(habit: MyraHabit): String = listOf(
        toHex(habit.id),
        toHex(habit.title),
        habit.completedDates.sorted().joinToString(","),
    ).joinToString("|")

    fun decode(row: String): MyraHabit? {
        return try {
        val parts = row.split('|', limit = 3)
        if (parts.size != 3) return null
        val id = fromHex(parts[0]) ?: return null
        val title = fromHex(parts[1]) ?: return null
        if (parts[2].isNotEmpty() && parts[2].split(',').size > MAX_COMPLETIONS) return null
        val dates = if (parts[2].isEmpty()) emptySet() else parts[2].split(',').toSet()
        if (dates.size != (if (parts[2].isEmpty()) 0 else parts[2].split(',').size)) return null
        if (dates.any { !isValidDate(it) }) return null
        val habit = create(title, id) ?: return null
        habit.copy(completedDates = dates)
        } catch (_: Exception) { null }
    }

    private fun parseCalendar(value: String): Calendar? {
        return try {
            val format = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply { isLenient = false }
            val position = ParsePosition(0)
            val date = format.parse(value, position)?.takeIf { position.index == value.length } ?: return null
            Calendar.getInstance().apply { time = date }
        } catch (_: Exception) { null }
    }

    private fun formatDate(calendar: Calendar): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).format(calendar.time)

    private fun toHex(value: String): String = buildString {
        value.toByteArray(Charsets.UTF_8).forEach { byte ->
            val unsigned = byte.toInt() and 0xff
            append(HEX[unsigned ushr 4]); append(HEX[unsigned and 0x0f])
        }
    }

    private fun fromHex(value: String): String? {
        return try {
            if (value.length % 2 != 0) return null
            val bytes = ByteArray(value.length / 2)
            for (i in bytes.indices) {
                val high = HEX.indexOf(value[i * 2]); val low = HEX.indexOf(value[i * 2 + 1])
                if (high < 0 || low < 0) return null
                bytes[i] = ((high shl 4) or low).toByte()
            }
            Charsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(bytes)).toString()
        } catch (_: Exception) { null }
    }
}
