package com.myra.ultra.nativeapp

import kotlin.math.roundToInt

/** The legacy Termux volume streams that have direct Android AudioManager equivalents. */
internal enum class MyraVolumeStream(val key: String, val label: String) {
    MUSIC("music", "Music"),
    RING("ring", "Ring"),
    ALARM("alarm", "Alarm"),
    NOTIFICATION("notification", "Notification"),
    SYSTEM("system", "System"),
    CALL("call", "Voice call");

    companion object {
        fun fromKey(key: String): MyraVolumeStream? = values().firstOrNull { it.key == key }
    }
}

internal object MyraVolumeControl {
    fun isValidLevel(level: Int, minimum: Int, maximum: Int): Boolean =
        minimum >= 0 && maximum >= minimum && level in minimum..maximum

    fun isSupportedKey(key: String): Boolean = MyraVolumeStream.fromKey(key) != null

    fun levelForPercent(percent: Int, minimum: Int, maximum: Int): Int? {
        if (percent !in 0..100 || minimum < 0 || maximum < minimum) return null
        return (minimum + (maximum - minimum) * (percent / 100.0)).roundToInt()
    }
}

internal data class VolumeUiState(
    val current: Int? = null,
    val minimum: Int? = null,
    val maximum: Int? = null,
    val message: String = "Choose a stream; opening Tools does not change volume.",
)
