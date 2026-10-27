package com.myra.ultra.nativeapp

/** Per-window brightness levels; this does not read or change device-wide display settings. */
internal object MyraWindowBrightness {
    const val MIN_LEVEL = 0
    const val MAX_LEVEL = 255
    const val DEFAULT_LEVEL = 128

    fun normalizeLevel(level: Int): Int = level.coerceIn(MIN_LEVEL, MAX_LEVEL)

    fun isValidLevel(level: Int): Boolean = level in MIN_LEVEL..MAX_LEVEL

    fun toWindowBrightness(level: Int): Float = normalizeLevel(level).toFloat() / MAX_LEVEL
}
