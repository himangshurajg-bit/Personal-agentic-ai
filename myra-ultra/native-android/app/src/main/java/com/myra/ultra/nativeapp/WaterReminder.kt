package com.myra.ultra.nativeapp

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import java.util.TimeZone
import java.util.concurrent.TimeUnit

/** Optional, user-enabled once-daily nudge, scheduled as best-effort work at a chosen local time. */
internal object WaterReminderScheduler {
    private const val WORK_NAME = "myra-water-target-reminder"
    private const val CHANNEL_ID = "myra_water_target_reminders"
    private const val CHANNEL_NAME = "Water log reminders"
    private const val NOTIFICATION_ID = 42017
    private const val KEY_MINUTES = "reminder_minutes"
    private const val KEY_LOCAL_DATE = "reminder_local_date"

    fun sync(context: Context, enabled: Boolean, targetMilliliters: Int, timeText: String, nowMillis: Long = System.currentTimeMillis()) {
        val minutes = WaterReminderPolicy.parseMinutesSinceMidnight(timeText)
        if (!enabled || targetMilliliters !in WaterTarget.MIN_MILLILITERS..WaterTarget.MAX_MILLILITERS || minutes == null || !hasNotificationPermission(context)) {
            cancel(context)
            return
        }
        val next = WaterReminderPolicy.nextOccurrence(nowMillis, minutes) ?: run { cancel(context); return }
        WorkManager.getInstance(context.applicationContext)
            .enqueueUniqueWork(WORK_NAME, ExistingWorkPolicy.REPLACE, request(nowMillis, next, minutes))
    }

    fun cancel(context: Context) {
        WorkManager.getInstance(context.applicationContext).cancelUniqueWork(WORK_NAME)
    }

    internal fun enqueueNext(context: Context, minutes: Int, nowMillis: Long = System.currentTimeMillis()) {
        if (minutes !in 0 until 24 * 60 || !hasNotificationPermission(context)) return
        val target = context.getSharedPreferences("myra_native_water", Context.MODE_PRIVATE).getInt("daily_target_ml", 0)
        val enabled = context.getSharedPreferences("myra_native_water", Context.MODE_PRIVATE).getBoolean("daily_reminder_enabled", false)
        if (!enabled || target !in WaterTarget.MIN_MILLILITERS..WaterTarget.MAX_MILLILITERS) return
        val next = WaterReminderPolicy.nextOccurrence(nowMillis, minutes) ?: return
        WorkManager.getInstance(context.applicationContext)
            .enqueueUniqueWork(WORK_NAME, ExistingWorkPolicy.APPEND_OR_REPLACE, request(nowMillis, next, minutes))
    }

    private fun request(nowMillis: Long, runAtMillis: Long, minutes: Int) =
        OneTimeWorkRequestBuilder<WaterReminderWorker>()
            .setInitialDelay((runAtMillis - nowMillis).coerceAtLeast(0L), TimeUnit.MILLISECONDS)
            .setInputData(workDataOf(
                KEY_MINUTES to minutes,
                KEY_LOCAL_DATE to WaterReminderPolicy.localDateKey(runAtMillis),
            ))
            .addTag(WORK_NAME)
            .build()

    internal fun showNotification(context: Context) {
        if (!hasNotificationPermission(context)) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_DEFAULT))
        }
        val openApp = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pending = PendingIntent.getActivity(context, NOTIFICATION_ID, openApp, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, CHANNEL_ID) else Notification.Builder(context)
        manager.notify(NOTIFICATION_ID, builder
            .setSmallIcon(android.R.drawable.ic_popup_reminder)
            .setContentTitle("Water log reminder")
            .setContentText("Your log is still below the daily target you chose.")
            .setContentIntent(pending)
            .setAutoCancel(true)
            .build())
    }
}

class WaterReminderWorker(context: Context, parameters: WorkerParameters) : Worker(context, parameters) {
    override fun doWork(): Result {
        val minutes = inputData.getInt("reminder_minutes", -1)
        val expectedDate = inputData.getString("reminder_local_date") ?: return Result.failure()
        val prefs = applicationContext.getSharedPreferences("myra_native_water", Context.MODE_PRIVATE)
        val currentMinutes = WaterReminderPolicy.parseMinutesSinceMidnight(prefs.getString("daily_reminder_time", "").orEmpty())
        val target = prefs.getInt("daily_target_ml", 0)
        val enabled = prefs.getBoolean("daily_reminder_enabled", false)
        val now = System.currentTimeMillis()
        if (enabled && currentMinutes == minutes && target in WaterTarget.MIN_MILLILITERS..WaterTarget.MAX_MILLILITERS && hasNotificationPermission(applicationContext)) {
            // A late delivery after a timezone/date change skips yesterday's nudge instead of duplicating it today.
            if (expectedDate == WaterReminderPolicy.localDateKey(now)) {
                val total = prefs.getStringSet("items", emptySet()).orEmpty()
                    .mapNotNull(WaterLog::decode)
                    .let { WaterLog.totalForDate(it, expectedDate) }
                if (WaterReminderPolicy.shouldNotify(enabled, target, total)) WaterReminderScheduler.showNotification(applicationContext)
            }
            WaterReminderScheduler.enqueueNext(applicationContext, minutes, now)
        }
        return Result.success()
    }
}
