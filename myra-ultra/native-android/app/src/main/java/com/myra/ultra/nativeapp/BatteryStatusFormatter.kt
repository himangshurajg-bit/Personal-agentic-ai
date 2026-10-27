package com.myra.ultra.nativeapp

/** Formats only fields exposed by Android's one-shot BATTERY_CHANGED broadcast. */
internal object BatteryStatusFormatter {
    fun format(
        percent: Int,
        status: Int?,
        health: Int?,
        temperatureTenthsC: Int?,
        voltageMillivolts: Int?,
        technology: String?,
    ): String {
        if (percent !in 0..100) {
            return "Battery percentage unavailable; Android did not return a valid reading."
        }
        val parts = mutableListOf(
            "$percent%",
            when (status) {
                android.os.BatteryManager.BATTERY_STATUS_CHARGING,
                android.os.BatteryManager.BATTERY_STATUS_FULL -> "charging or full"
                android.os.BatteryManager.BATTERY_STATUS_DISCHARGING,
                android.os.BatteryManager.BATTERY_STATUS_NOT_CHARGING -> "not charging"
                else -> "charging state unavailable"
            },
        )
        health?.let { value ->
            val label = when (value) {
                android.os.BatteryManager.BATTERY_HEALTH_GOOD -> "good"
                android.os.BatteryManager.BATTERY_HEALTH_OVERHEAT -> "overheating"
                android.os.BatteryManager.BATTERY_HEALTH_DEAD -> "dead"
                android.os.BatteryManager.BATTERY_HEALTH_OVER_VOLTAGE -> "over-voltage"
                android.os.BatteryManager.BATTERY_HEALTH_UNSPECIFIED_FAILURE -> "unspecified failure"
                android.os.BatteryManager.BATTERY_HEALTH_COLD -> "cold"
                else -> null
            }
            if (label != null) parts += "health: $label"
        }
        temperatureTenthsC?.takeIf { it in -400..1000 }?.let {
            parts += "temperature: ${"%.1f".format(java.util.Locale.ROOT, it / 10.0)} °C"
        }
        voltageMillivolts?.takeIf { it in 1..20_000 }?.let {
            parts += "voltage: ${"%.2f".format(java.util.Locale.ROOT, it / 1000.0)} V"
        }
        technology?.trim()?.takeIf { it.isNotEmpty() }?.let { raw ->
            val safe = raw.filter { it.isLetterOrDigit() || it in " ._+-/" }.take(40).trim()
            if (safe.isNotEmpty()) parts += "chemistry: $safe"
        }
        return parts.joinToString(" · ")
    }
}
