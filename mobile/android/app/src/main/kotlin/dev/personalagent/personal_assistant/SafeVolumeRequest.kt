package dev.personalagent.personal_assistant

import kotlin.math.roundToInt

internal object SafeVolumeRequest {
    val streams = setOf("music", "ring", "alarm", "notification", "system", "call")

    fun isValidStream(value: Any?): Boolean = value is String && value in streams

    fun percent(value: Any?): Int? {
        val percent = when (value) {
            is Int -> value
            is Long -> value.takeIf { it in Int.MIN_VALUE..Int.MAX_VALUE }?.toInt()
            else -> null
        } ?: return null
        return percent.takeIf { it in 0..100 }
    }

    fun levelForPercent(percent: Int, min: Int, max: Int): Int? {
        if (percent !in 0..100 || min < 0 || max < min) return null
        return (min + (max - min) * (percent / 100.0)).roundToInt()
    }

    fun percentForLevel(level: Int, min: Int, max: Int): Int? {
        if (min < 0 || max < min || level !in min..max) return null
        if (max == min) return 0
        return (((level - min).toDouble() / (max - min)) * 100).roundToInt()
    }
}
