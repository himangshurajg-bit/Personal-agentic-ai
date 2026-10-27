package com.myra.ultra.nativeapp

/** A user-selected daily intake goal; zero/unset deliberately has no assumed target. */
internal object WaterTarget {
    const val MIN_MILLILITERS = 250
    const val MAX_MILLILITERS = 20_000

    fun parseMilliliters(input: String): Int? = input.trim().toIntOrNull()
        ?.takeIf { it in MIN_MILLILITERS..MAX_MILLILITERS }

    fun progress(totalMilliliters: Long, targetMilliliters: Int): Float? {
        if (targetMilliliters !in MIN_MILLILITERS..MAX_MILLILITERS) return null
        return (totalMilliliters.coerceAtLeast(0).toDouble() / targetMilliliters)
            .coerceIn(0.0, 1.0).toFloat()
    }

    fun remaining(totalMilliliters: Long, targetMilliliters: Int): Long? {
        if (targetMilliliters !in MIN_MILLILITERS..MAX_MILLILITERS) return null
        return (targetMilliliters.toLong() - totalMilliliters.coerceAtLeast(0)).coerceAtLeast(0)
    }
}
