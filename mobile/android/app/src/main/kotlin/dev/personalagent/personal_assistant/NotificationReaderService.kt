package dev.personalagent.personal_assistant

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.app.Notification

/** Android grants this service only after the owner enables notification access in system settings. */
class NotificationReaderService : NotificationListenerService() {
    override fun onListenerConnected() {
        super.onListenerConnected()
        instance = this
    }

    override fun onListenerDisconnected() {
        if (instance === this) instance = null
        super.onListenerDisconnected()
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }

    companion object {
        @Volatile private var instance: NotificationReaderService? = null

        fun readActiveNotifications(): List<Map<String, Any>>? {
            val service = instance ?: return null
            return try {
                service.activeNotifications.orEmpty()
                    .asSequence()
                    .filterNot { it.packageName == service.packageName }
                    .sortedByDescending { it.postTime }
                    .take(10)
                    .mapNotNull { sbn ->
                        val extras = sbn.notification.extras ?: return@mapNotNull null
                        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim().orEmpty()
                        val text = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
                            ?: extras.getCharSequence(Notification.EXTRA_TEXT))?.toString()?.trim().orEmpty()
                        if (title.isEmpty() && text.isEmpty()) return@mapNotNull null
                        mapOf(
                            "package" to sbn.packageName,
                            "title" to title.take(160),
                            "text" to text.take(500),
                            "posted_at" to sbn.postTime,
                        )
                    }
                    .toList()
            } catch (_: SecurityException) {
                null
            }
        }
    }
}
