package dev.personalagent.personal_assistant

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/** Visible, user-started lifetime guard for opt-in background mic capture. */
class LiveConversationService : Service() {
    companion object {
        const val ACTION_START = "dev.personalagent.personal_assistant.LIVE_START"
        const val ACTION_STOP = "dev.personalagent.personal_assistant.LIVE_STOP"
        const val ACTION_STOP_REQUESTED = "dev.personalagent.personal_assistant.LIVE_STOP_REQUESTED"
        private const val CHANNEL_ID = "live_conversation"
        private const val NOTIFICATION_ID = 8042
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            sendBroadcast(Intent(ACTION_STOP_REQUESTED).setPackage(packageName))
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf(startId)
            return START_NOT_STICKY
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            stopSelf(startId)
            return START_NOT_STICKY
        }
        createNotificationChannel()
        val notification = buildNotification()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (_: SecurityException) {
            stopSelf(startId)
            return START_NOT_STICKY
        }
        return START_NOT_STICKY
    }

    private fun createNotificationChannel() {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Live conversation microphone",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Shows when an explicitly started live conversation is using the microphone."
                setShowBadge(false)
            },
        )
    }

    private fun buildNotification(): Notification {
        val stop = PendingIntent.getService(
            this,
            NOTIFICATION_ID,
            Intent(this, LiveConversationService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Personal AI · Live Conversation")
            .setContentText("Microphone is active. Tap Stop to end the session.")
            .setCategory(Notification.CATEGORY_SERVICE)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .addAction(Notification.Action.Builder(null, "Stop", stop).build())
            .build()
    }
}
