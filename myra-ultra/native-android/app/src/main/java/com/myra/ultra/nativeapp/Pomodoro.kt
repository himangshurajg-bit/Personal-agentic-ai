package com.myra.ultra.nativeapp

import kotlin.math.ceil

internal enum class FocusPhase(val label: String, val durationSeconds: Int) {
    FOCUS("Focus", 25 * 60),
    BREAK("Break", 5 * 60),
}

internal object PomodoroTimer {
    fun remainingSeconds(deadlineMillis: Long?, pausedSeconds: Int, nowMillis: Long): Int {
        if (deadlineMillis == null) return pausedSeconds.coerceAtLeast(0)
        val millis = (deadlineMillis - nowMillis).coerceAtLeast(0)
        return ceil(millis / 1000.0).toInt()
    }

    fun deadlineAfter(nowMillis: Long, seconds: Int): Long = nowMillis + seconds.coerceAtLeast(0) * 1000L

    fun format(seconds: Int): String {
        val safe = seconds.coerceAtLeast(0)
        return "%02d:%02d".format(safe / 60, safe % 60)
    }
}
