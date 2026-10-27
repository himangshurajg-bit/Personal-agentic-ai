package com.myra.ultra.nativeapp

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import java.text.ParsePosition
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.concurrent.TimeUnit

/** Strict local-time parser used by task forms and reminder scheduling. Blank date/time means no due date. */
internal fun parseTaskDueAt(dateText: String, timeText: String, timeZone: TimeZone = TimeZone.getDefault()): Long? {
    val date = dateText.trim()
    val time = timeText.trim()
    if (date.isEmpty() && time.isEmpty()) return null
    if (date.isEmpty() || !Regex("\\d{4}-\\d{2}-\\d{2}").matches(date)) return null
    val normalizedTime = if (time.isEmpty()) "00:00" else time
    if (!Regex("\\d{2}:\\d{2}").matches(normalizedTime)) return null
    val parser = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US).apply {
        isLenient = false
        this.timeZone = timeZone
    }
    val source = "$date $normalizedTime"
    val position = ParsePosition(0)
    val parsed = parser.parse(source, position) ?: return null
    return parsed.time.takeIf { position.index == source.length && parser.format(parsed) == source }
}

internal fun isTaskReminderEligible(task: MyraTask, nowMillis: Long): Boolean =
    task.reminderEnabled && !task.done && task.dueHasTime && task.dueAtMillis != null && task.dueAtMillis >= nowMillis

/** Advance daily or weekly reminders by calendar days, preserving local wall-clock time across DST. */
internal fun nextRecurringDueAt(
    dueAtMillis: Long,
    repeatEveryDays: Int,
    nowMillis: Long,
    timeZone: TimeZone = TimeZone.getDefault(),
): Long? {
    if (repeatEveryDays != 1 && repeatEveryDays != 7) return null
    val calendar = Calendar.getInstance(timeZone).apply { timeInMillis = dueAtMillis }
    do {
        calendar.add(Calendar.DAY_OF_MONTH, repeatEveryDays)
    } while (calendar.timeInMillis <= nowMillis)
    return calendar.timeInMillis
}

internal fun hasNotificationPermission(context: Context): Boolean =
    Build.VERSION.SDK_INT < 33 || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

internal object TaskReminderScheduler {
    private const val CHANNEL_ID = "myra_task_reminders"
    private const val CHANNEL_NAME = "Task reminders"
    private const val WORK_PREFIX = "myra-task-reminder-"
    private const val KEY_TASK_ID = "task_id"
    private const val KEY_TITLE = "task_title"
    private const val KEY_DUE_AT = "due_at_millis"

    fun sync(context: Context, task: MyraTask, nowMillis: Long = System.currentTimeMillis()) {
        val workManager = WorkManager.getInstance(context.applicationContext)
        val workName = WORK_PREFIX + task.id
        if (!isTaskReminderEligible(task, nowMillis) || !hasNotificationPermission(context)) {
            workManager.cancelUniqueWork(workName)
            return
        }
        workManager.enqueueUniqueWork(workName, ExistingWorkPolicy.REPLACE, request(task, nowMillis))
    }

    /** Enqueue the next occurrence behind the worker currently delivering this occurrence. */
    internal fun enqueueNextOccurrence(context: Context, task: MyraTask, nowMillis: Long = System.currentTimeMillis()) {
        if (!isTaskReminderEligible(task, nowMillis) || !hasNotificationPermission(context)) return
        val workName = WORK_PREFIX + task.id
        WorkManager.getInstance(context.applicationContext)
            .enqueueUniqueWork(workName, ExistingWorkPolicy.APPEND_OR_REPLACE, request(task, nowMillis))
    }

    private fun request(task: MyraTask, nowMillis: Long): androidx.work.OneTimeWorkRequest {
        val workName = WORK_PREFIX + task.id
        val due = requireNotNull(task.dueAtMillis)
        return OneTimeWorkRequestBuilder<TaskReminderWorker>()
            .setInitialDelay((due - nowMillis).coerceAtLeast(0L), TimeUnit.MILLISECONDS)
            .setInputData(workDataOf(KEY_TASK_ID to task.id, KEY_TITLE to task.title, KEY_DUE_AT to due))
            .addTag(workName)
            .addTag("$workName-due-$due")
            .build()
    }

    fun cancel(context: Context, taskId: String) {
        WorkManager.getInstance(context.applicationContext).cancelUniqueWork(WORK_PREFIX + taskId)
    }

    suspend fun ensureScheduled(context: Context, task: MyraTask, nowMillis: Long = System.currentTimeMillis()) {
        if (!isTaskReminderEligible(task, nowMillis) || !hasNotificationPermission(context)) {
            cancel(context, task.id)
            return
        }
        val workName = WORK_PREFIX + task.id
        val due = requireNotNull(task.dueAtMillis)
        val existing = try {
            withContext(Dispatchers.IO) { WorkManager.getInstance(context.applicationContext).getWorkInfosForUniqueWork(workName).get() }
        } catch (_: Exception) { emptyList() }
        val dueTag = "$workName-due-$due"
        val sameScheduleExists = existing.any { info ->
            val active = info.state == androidx.work.WorkInfo.State.ENQUEUED || info.state == androidx.work.WorkInfo.State.RUNNING || info.state == androidx.work.WorkInfo.State.BLOCKED
            val alreadyDelivered = info.state == androidx.work.WorkInfo.State.SUCCEEDED && info.outputData.getLong(KEY_DUE_AT, Long.MIN_VALUE) == due
            (active && dueTag in info.tags) || alreadyDelivered
        }
        if (!sameScheduleExists) sync(context, task, nowMillis)
    }

    internal fun showNotification(context: Context, taskId: String, title: String) {
        if (!hasNotificationPermission(context)) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_DEFAULT))
        }
        val openApp = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pending = PendingIntent.getActivity(context, taskId.hashCode(), openApp, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, CHANNEL_ID) else Notification.Builder(context)
        val notification = builder
            .setSmallIcon(android.R.drawable.ic_popup_reminder)
            .setContentTitle("Task reminder")
            .setContentText(title.ifBlank { "A task is due" })
            .setContentIntent(pending)
            .setAutoCancel(true)
            .build()
        manager.notify(taskId.hashCode(), notification)
    }
}

class TaskReminderWorker(context: Context, parameters: WorkerParameters) : Worker(context, parameters) {
    override fun doWork(): Result {
        val taskId = inputData.getString("task_id") ?: return Result.failure()
        val expectedDue = inputData.getLong("due_at_millis", Long.MIN_VALUE)
        val saved = applicationContext.getSharedPreferences("myra_native_tasks", Context.MODE_PRIVATE)
            .getStringSet("items", emptySet()).orEmpty().mapNotNull(::decodeTask).firstOrNull { it.id == taskId }
            ?: return Result.success()
        if (saved.done || !saved.reminderEnabled || !saved.dueHasTime || saved.dueAtMillis != expectedDue) return Result.success()
        if (expectedDue > System.currentTimeMillis()) return Result.retry()
        if (hasNotificationPermission(applicationContext)) {
            TaskReminderScheduler.showNotification(applicationContext, taskId, saved.title)
        }
        if (saved.repeatEveryDays == 1 || saved.repeatEveryDays == 7) {
            val now = System.currentTimeMillis()
            val nextDue = nextRecurringDueAt(expectedDue, saved.repeatEveryDays, now)
                ?: return Result.success(workDataOf("due_at_millis" to expectedDue))
            val prefs = applicationContext.getSharedPreferences("myra_native_tasks", Context.MODE_PRIVATE)
            synchronized(TASK_PREFS_LOCK) {
                val rows = prefs.getStringSet("items", emptySet()).orEmpty()
                val current = rows.firstOrNull { decodeTask(it)?.id == taskId }
                // Do not overwrite an edit, completion or delete that raced this notification.
                if (current == null || decodeTask(current) != saved) {
                    return Result.success(workDataOf("due_at_millis" to expectedDue))
                }
                val updated = saved.copy(dueAtMillis = nextDue)
                prefs.edit().putStringSet("items", rows.filterNot { it == current }.toSet() + encodeTask(updated)).commit()
                TaskReminderScheduler.enqueueNextOccurrence(applicationContext, updated, now)
            }
            return Result.success(workDataOf("due_at_millis" to expectedDue))
        }
        return Result.success(workDataOf("due_at_millis" to expectedDue))
    }
}
