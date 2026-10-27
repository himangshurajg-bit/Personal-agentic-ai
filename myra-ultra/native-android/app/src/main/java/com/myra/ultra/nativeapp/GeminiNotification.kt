package com.myra.ultra.nativeapp

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import java.io.IOException
import org.json.JSONObject

internal data class GeminiNotificationRequest(val title: String, val text: String)

/** Strictly bounded local-notification content; actual posting occurs only after user review. */
internal object GeminiNotificationPolicy {
    const val TOOL = "post_notification"
    const val TITLE_LIMIT = 80
    const val TEXT_LIMIT = 300

    fun request(args: JSONObject): GeminiNotificationRequest {
        if (args.length() != 2 || !args.has("title") || !args.has("text")) {
            throw IOException("Gemini requested unexpected notification arguments; nothing was posted.")
        }
        val title = args.opt("title") as? String
            ?: throw IOException("Gemini requested an invalid notification title; nothing was posted.")
        val text = args.opt("text") as? String
            ?: throw IOException("Gemini requested invalid notification text; nothing was posted.")
        if (title.isBlank() || title.length > TITLE_LIMIT || title.any { it.isISOControl() }) {
            throw IOException("Gemini requested an empty, oversized, or invalid notification title; nothing was posted.")
        }
        if (text.isBlank() || text.length > TEXT_LIMIT || text.any { it.isISOControl() && it != '\n' && it != '\r' && it != '\t' }) {
            throw IOException("Gemini requested empty, oversized, or invalid notification text; nothing was posted.")
        }
        return GeminiNotificationRequest(title, text)
    }

    /** Require the latest user turn to explicitly ask for a notification; model calls alone do not authorize it. */
    fun hasExplicitIntent(userText: String): Boolean {
        val text = userText.lowercase()
        if (Regex("\\b(don't|do not|never|stop|cancel)\\b.{0,40}\\b(notify|notification|alert)\\b").containsMatchIn(text)) return false
        // This tool posts immediately; future/timed language belongs to a scheduler and must not trigger it.
        if (Regex("\\b(later|tomorrow|tonight|when|after|before|at|schedule|scheduled|remind)\\b").containsMatchIn(text)) return false
        val directNotify = Regex("\\bnotify\\s+(me|us)\\b").containsMatchIn(text)
        val action = Regex("\\b(show|send|post|create|make|display|raise)\\b.{0,60}\\b(notification|alert)\\b|\\b(notification|alert)\\b.{0,60}\\b(show|send|post|create|make|display|raise)\\b")
            .containsMatchIn(text)
        return directNotify || action
    }
}

/** Posts a reviewed notification locally. Caller must check/request POST_NOTIFICATIONS first. */
internal fun postReviewedNotification(context: Context, request: GeminiNotificationRequest): Boolean {
    if (!hasNotificationPermission(context)) return false
    val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return false
    val channelId = "myra_user_notifications"
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        manager.createNotificationChannel(NotificationChannel(channelId, "MYRA notifications", NotificationManager.IMPORTANCE_DEFAULT))
    }
    val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        Notification.Builder(context, channelId)
    } else {
        @Suppress("DEPRECATION") Notification.Builder(context)
    }
    val notification = builder
        .setSmallIcon(android.R.drawable.ic_dialog_info)
        .setContentTitle(request.title)
        .setContentText(request.text)
        .setStyle(Notification.BigTextStyle().bigText(request.text))
        .setAutoCancel(true)
        .build()
    manager.notify((System.currentTimeMillis() and 0x7fffffff).toInt(), notification)
    return true
}
