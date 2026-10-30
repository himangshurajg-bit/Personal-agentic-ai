package dev.personalagent.personal_assistant

import android.app.ActivityManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.res.Configuration
import android.media.AudioManager
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.os.StatFs
import android.os.SystemClock
import android.provider.Settings
import android.util.DisplayMetrics
import android.view.WindowManager
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

/** On-demand, read-only device facts. Values are local to this phone and are never persisted. */
internal object DeviceStatusSnapshot {
    fun read(context: Context): Map<String, Any?> {
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        val memory = ActivityManager.MemoryInfo()
        val memoryAvailable = runCatching {
            activityManager?.getMemoryInfo(memory)
            if (activityManager == null) null else memory.availMem
        }.getOrNull()
        val memoryTotal = if (activityManager == null) null else runCatching { memory.totalMem }.getOrNull()

        val storage = runCatching { StatFs(Environment.getDataDirectory().absolutePath) }.getOrNull()
        val storageBlockSize = storage?.blockSizeLong
        val storageTotal = safeProduct(storageBlockSize, storage?.blockCountLong)
        val storageAvailable = safeProduct(storageBlockSize, storage?.availableBlocksLong)

        val metrics = DisplayMetrics()
        val displayRead = runCatching {
            val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as? WindowManager
            val display = windowManager?.defaultDisplay
            if (display == null) null else {
                display.getRealMetrics(metrics)
                display
            }
        }.getOrNull()

        val audio = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        val power = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        val battery = runCatching {
            context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        }.getOrNull()
        val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val version = runCatching {
            @Suppress("DEPRECATION")
            context.packageManager.getPackageInfo(context.packageName, 0)
        }.getOrNull()
        val brightness = runCatching {
            Settings.System.getInt(context.contentResolver, Settings.System.SCREEN_BRIGHTNESS)
                .takeIf { it in 0..255 }
        }.getOrNull()
        val locale = runCatching { Locale.getDefault().toLanguageTag() }.getOrNull()
        val localTime = runCatching {
            ZonedDateTime.now().format(DateTimeFormatter.ISO_OFFSET_DATE_TIME)
        }.getOrNull()

        return mapOf(
            "local_time" to localTime,
            "time_zone" to runCatching { java.util.TimeZone.getDefault().id }.getOrNull(),
            "android_release" to Build.VERSION.RELEASE,
            "android_sdk" to Build.VERSION.SDK_INT,
            "security_patch" to Build.VERSION.SECURITY_PATCH,
            "storage_total_bytes" to storageTotal,
            "storage_available_bytes" to storageAvailable,
            "app_version" to version?.versionName,
            "app_build" to version?.let {
                @Suppress("DEPRECATION")
                it.versionCode
            },
            "memory_total_bytes" to memoryTotal,
            "memory_available_bytes" to memoryAvailable,
            "display_width_px" to if (displayRead == null) null else metrics.widthPixels,
            "display_height_px" to if (displayRead == null) null else metrics.heightPixels,
            "display_density_dpi" to if (displayRead == null) null else metrics.densityDpi,
            "display_refresh_hz" to runCatching { displayRead?.refreshRate?.toDouble() }.getOrNull(),
            "ringer_mode" to runCatching { ringerModeLabel(audio?.ringerMode) }.getOrNull(),
            "locale" to locale,
            "system_theme" to themeLabel(context.resources.configuration.uiMode),
            "thermal_status" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                runCatching { power?.currentThermalStatus?.let(::thermalStatusLabel) }.getOrNull()
            } else null,
            "battery_saver" to runCatching { power?.isPowerSaveMode }.getOrNull(),
            "brightness_level" to brightness,
            "brightness_percent" to brightness?.let { ((it * 100.0) / 255.0).toInt() },
            "notifications_enabled" to runCatching { notificationManager?.areNotificationsEnabled() }.getOrNull(),
            "uptime_ms" to SystemClock.elapsedRealtime(),
            "battery_percent" to batteryPercent(level, scale),
            "battery_status" to battery?.getIntExtra(BatteryManager.EXTRA_STATUS, -1)?.let(::batteryStatusLabel),
            "battery_health" to battery?.getIntExtra(BatteryManager.EXTRA_HEALTH, -1)?.let(::batteryHealthLabel),
            "battery_temperature_c" to battery?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1)
                ?.takeIf { it >= 0 }?.div(10.0),
            "battery_voltage_mv" to battery?.getIntExtra(BatteryManager.EXTRA_VOLTAGE, -1)?.takeIf { it >= 0 },
            "battery_chemistry" to battery?.getStringExtra(BatteryManager.EXTRA_TECHNOLOGY),
        )
    }

    fun batteryPercent(level: Int, scale: Int): Int? =
        if (scale <= 0 || level < 0 || level > scale) null else (level * 100.0 / scale).toInt()

    fun ringerModeLabel(mode: Int?): String? = when (mode) {
        AudioManager.RINGER_MODE_NORMAL -> "normal"
        AudioManager.RINGER_MODE_VIBRATE -> "vibrate"
        AudioManager.RINGER_MODE_SILENT -> "silent"
        else -> null
    }

    fun themeLabel(uiMode: Int): String? = when (uiMode and Configuration.UI_MODE_NIGHT_MASK) {
        Configuration.UI_MODE_NIGHT_NO -> "light"
        Configuration.UI_MODE_NIGHT_YES -> "dark"
        else -> null
    }

    fun thermalStatusLabel(status: Int): String? = when (status) {
        PowerManager.THERMAL_STATUS_NONE -> "none"
        PowerManager.THERMAL_STATUS_LIGHT -> "light"
        PowerManager.THERMAL_STATUS_MODERATE -> "moderate"
        PowerManager.THERMAL_STATUS_SEVERE -> "severe"
        PowerManager.THERMAL_STATUS_CRITICAL -> "critical"
        PowerManager.THERMAL_STATUS_EMERGENCY -> "emergency"
        PowerManager.THERMAL_STATUS_SHUTDOWN -> "shutdown"
        else -> null
    }

    fun batteryStatusLabel(status: Int): String? = when (status) {
        BatteryManager.BATTERY_STATUS_CHARGING -> "charging"
        BatteryManager.BATTERY_STATUS_DISCHARGING -> "discharging"
        BatteryManager.BATTERY_STATUS_NOT_CHARGING -> "not charging"
        BatteryManager.BATTERY_STATUS_FULL -> "full"
        BatteryManager.BATTERY_STATUS_UNKNOWN -> "unknown"
        else -> null
    }

    fun batteryHealthLabel(health: Int): String? = when (health) {
        BatteryManager.BATTERY_HEALTH_GOOD -> "good"
        BatteryManager.BATTERY_HEALTH_OVERHEAT -> "overheat"
        BatteryManager.BATTERY_HEALTH_DEAD -> "dead"
        BatteryManager.BATTERY_HEALTH_OVER_VOLTAGE -> "over voltage"
        BatteryManager.BATTERY_HEALTH_UNSPECIFIED_FAILURE -> "unspecified failure"
        BatteryManager.BATTERY_HEALTH_COLD -> "cold"
        BatteryManager.BATTERY_HEALTH_UNKNOWN -> "unknown"
        else -> null
    }

    private fun safeProduct(left: Long?, right: Long?): Long? = runCatching {
        if (left == null || right == null || left < 0 || right < 0) null
        else Math.multiplyExact(left, right)
    }.getOrNull()
}
