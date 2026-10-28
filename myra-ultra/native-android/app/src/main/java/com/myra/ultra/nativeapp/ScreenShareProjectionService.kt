package com.myra.ultra.nativeapp

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.util.DisplayMetrics
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Captures only after the user-granted MediaProjection result and streams to an approved session. */
class ScreenShareProjectionService : Service() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val ioScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val captureThread = HandlerThread("MYRA-screen-share-capture").apply { start() }
    private val captureHandler by lazy { Handler(captureThread.looper) }
    private val network = ScreenShareNetwork()
    private val frameExecutor: ExecutorService = Executors.newSingleThreadExecutor { task ->
        Thread(task, "MYRA-screen-share-encoder").apply { isDaemon = true }
    }
    private val encoding = AtomicBoolean(false)

    @Volatile private var socket: WebSocket? = null
    @Volatile private var streamReady = false
    @Volatile private var isStopping = false
    private var credentials: ScreenShareCredentials? = null
    private var sessionId: String? = null
    private var projection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var outputWidth = 0
    private var outputHeight = 0
    private var notificationId = 8120

    private val frameTicker = object : Runnable {
        override fun run() {
            if (!isRunning || isStopping || !streamReady) return
            captureLatestFrame()
            captureHandler.postDelayed(this, 1_000L / ScreenShareProtocol.SEND_FPS)
        }
    }

    private val projectionCallback = object : MediaProjection.Callback() {
        override fun onStop() {
            mainHandler.post { finishShare(sendEndRequest = true) }
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> finishShare(sendEndRequest = true)
            ACTION_START -> startApprovedShare(intent)
            else -> stopSelf(startId)
        }
        return START_NOT_STICKY
    }

    private fun startApprovedShare(intent: Intent) {
        if (isRunning || isStopping) return
        val code = intent.getIntExtra(EXTRA_RESULT_CODE, 0)
        val permissionData = if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(EXTRA_RESULT_DATA, Intent::class.java)
        } else {
            @Suppress("DEPRECATION") intent.getParcelableExtra(EXTRA_RESULT_DATA)
        }
        val id = intent.getStringExtra(EXTRA_SESSION_ID).orEmpty()
        if (code != android.app.Activity.RESULT_OK || permissionData == null || !ScreenShareProtocol.isValidSessionId(id)) {
            stopSelf()
            return
        }
        val saved = ScreenShareCredentialStore.read(this)
        if (saved == null) {
            stopSelf()
            return
        }
        credentials = saved
        sessionId = id
        isRunning = true
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    notificationId,
                    buildNotification("Waiting for Personal AI"),
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION,
                )
            } else {
                startForeground(notificationId, buildNotification("Waiting for Personal AI"))
            }
            val manager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            val grantedProjection = manager.getMediaProjection(code, permissionData)
            projection = grantedProjection
            grantedProjection.registerCallback(projectionCallback, mainHandler)
            prepareCaptureSize()
            openApprovedStream(saved, id)
            mainHandler.postDelayed({ finishShare(sendEndRequest = true) }, ScreenShareProtocol.MAX_STREAM_SECONDS * 1_000L)
        } catch (_: Exception) {
            finishShare(sendEndRequest = true)
        }
    }

    @Suppress("DEPRECATION")
    private fun prepareCaptureSize() {
        val metrics = DisplayMetrics()
        (getSystemService(Context.WINDOW_SERVICE) as WindowManager).defaultDisplay.getRealMetrics(metrics)
        val bounded = ScreenShareProtocol.captureSize(metrics.widthPixels, metrics.heightPixels)
        outputWidth = bounded.width
        outputHeight = bounded.height
    }

    private fun createVirtualDisplay(grantedProjection: MediaProjection) {
        val density = resources.displayMetrics.densityDpi.coerceAtLeast(1)
        val reader = ImageReader.newInstance(outputWidth, outputHeight, PixelFormat.RGBA_8888, 2)
        imageReader = reader
        virtualDisplay = grantedProjection.createVirtualDisplay(
            "MYRA approved screen share",
            outputWidth,
            outputHeight,
            density,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            reader.surface,
            null,
            captureHandler,
        ) ?: throw IOException("Android couldn't create a screen-share display.")
    }

    private fun openApprovedStream(saved: ScreenShareCredentials, id: String) {
        val created = network.openStream(saved, id, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                socket = webSocket
                val hello = ScreenShareProtocol.startMessage(outputWidth, outputHeight)
                if (!webSocket.send(hello.toString())) mainHandler.post { finishShare(sendEndRequest = true) }
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                val message = try { JSONObject(text) } catch (_: Exception) { null }
                val readyId = message?.optString("session_id").orEmpty()
                if (message != null && message.optString("type") == "ready" && readyId == sessionId &&
                    message.optInt("max_fps", 0) in 1..ScreenShareProtocol.MAX_FPS &&
                    message.optInt("max_frame_bytes", 0) in 1024..ScreenShareProtocol.MAX_FRAME_BYTES) {
                    mainHandler.post {
                        if (isStopping || streamReady || virtualDisplay != null) return@post
                        try {
                            val grantedProjection = projection
                                ?: throw IOException("Android screen-capture permission is no longer active.")
                            // Do not create a capture surface until the receiver has accepted this
                            // exact, approved session and replied ready on the authenticated stream.
                            createVirtualDisplay(grantedProjection)
                            streamReady = true
                            updateNotification("Screen sharing is active · tap Stop to end")
                            captureHandler.removeCallbacks(frameTicker)
                            captureHandler.post(frameTicker)
                        } catch (_: Exception) {
                            finishShare(sendEndRequest = true)
                        }
                    }
                } else {
                    mainHandler.post { finishShare(sendEndRequest = true) }
                }
            }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                mainHandler.post { finishShare(sendEndRequest = true) }
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                mainHandler.post { finishShare(sendEndRequest = false) }
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                mainHandler.post { finishShare(sendEndRequest = true) }
            }
        })
        socket = created
    }

    private fun captureLatestFrame() {
        if (isStopping || !streamReady || !encoding.compareAndSet(false, true)) return
        val image = try { imageReader?.acquireLatestImage() } catch (_: Exception) { null }
        if (image == null) {
            encoding.set(false)
            return
        }
        try {
            frameExecutor.execute {
                try {
                    val jpeg = image.use(::encodeJpeg)
                    val activeSocket = socket
                    if (jpeg != null && !isStopping && streamReady && activeSocket != null) {
                        // Drop rather than queue frames behind a slow network; cap the sender queue.
                        if (activeSocket.queueSize() + jpeg.size <= ScreenShareProtocol.MAX_FRAME_BYTES &&
                            !activeSocket.send(ByteString.of(*jpeg))) {
                            mainHandler.post { finishShare(sendEndRequest = true) }
                        }
                    }
                } catch (_: Exception) {
                    // Never log or persist captured pixels, frame bytes, or pairing credentials.
                } finally {
                    encoding.set(false)
                }
            }
        } catch (_: Exception) {
            image.close()
            encoding.set(false)
        }
    }

    private fun encodeJpeg(image: Image): ByteArray? {
        val plane = image.planes.firstOrNull() ?: return null
        val pixelStride = plane.pixelStride
        if (pixelStride < 4 || plane.rowStride < outputWidth * pixelStride) return null
        val rowPadding = plane.rowStride - pixelStride * outputWidth
        val paddedWidth = outputWidth + rowPadding / pixelStride
        val bitmap = Bitmap.createBitmap(paddedWidth, outputHeight, Bitmap.Config.ARGB_8888)
        try {
            bitmap.copyPixelsFromBuffer(plane.buffer)
            val crop = if (paddedWidth == outputWidth) bitmap else Bitmap.createBitmap(bitmap, 0, 0, outputWidth, outputHeight)
            try {
                val output = ByteArrayOutputStream(96 * 1024)
                if (!crop.compress(Bitmap.CompressFormat.JPEG, 55, output)) return null
                val bytes = output.toByteArray()
                if (bytes.size !in 4..ScreenShareProtocol.MAX_FRAME_BYTES ||
                    bytes[0] != 0xFF.toByte() || bytes[1] != 0xD8.toByte() ||
                    bytes[bytes.lastIndex - 1] != 0xFF.toByte() || bytes.last() != 0xD9.toByte()) return null
                return bytes
            } finally {
                if (crop !== bitmap) crop.recycle()
            }
        } finally {
            bitmap.recycle()
        }
    }

    private fun finishShare(sendEndRequest: Boolean) {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            mainHandler.post { finishShare(sendEndRequest) }
            return
        }
        if (isStopping) return
        isStopping = true
        isRunning = false
        streamReady = false
        captureHandler.removeCallbacks(frameTicker)
        val activeSocket = socket
        socket = null
        activeSocket?.close(1000, "Sender stopped")
        virtualDisplay?.release()
        virtualDisplay = null
        imageReader?.setOnImageAvailableListener(null, null)
        imageReader?.close()
        imageReader = null
        projection?.unregisterCallback(projectionCallback)
        projection?.stop()
        projection = null

        val saved = credentials
        val id = sessionId
        if (sendEndRequest && saved != null && id != null && ScreenShareProtocol.isValidSessionId(id)) {
            ioScope.launch {
                withContext(Dispatchers.IO) { runCatching { network.endSession(saved, id) } }
                finishService()
            }
        } else {
            finishService()
        }
    }

    @Suppress("DEPRECATION")
    private fun finishService() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) stopForeground(STOP_FOREGROUND_REMOVE)
        else stopForeground(true)
        stopSelf()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // The foreground notification keeps the stream visible; explicit Stop or OS revocation ends it.
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        if (!isStopping) {
            isStopping = true
            isRunning = false
            streamReady = false
            captureHandler.removeCallbacks(frameTicker)
            socket?.close(1000, "Service ended")
            virtualDisplay?.release()
            imageReader?.close()
            projection?.stop()
        }
        captureThread.quitSafely()
        frameExecutor.shutdownNow()
        ioScope.cancel()
        super.onDestroy()
    }

    private fun buildNotification(text: String): Notification {
        val stopIntent = Intent(this, ScreenShareProjectionService::class.java).setAction(ACTION_STOP)
        val stop = PendingIntent.getService(
            this,
            REQUEST_STOP,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_view)
            .setContentTitle("MYRA screen sharing")
            .setContentText(text)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .addAction(0, "Stop sharing", stop)
            .build()
    }

    private fun updateNotification(text: String) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(notificationId, buildNotification(text))
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Screen sharing", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Visible while MYRA is sharing your screen with a paired Personal AI receiver."
                },
            )
        }
    }

    companion object {
        const val ACTION_START = "com.myra.ultra.nativeapp.action.START_SCREEN_SHARE"
        const val ACTION_STOP = "com.myra.ultra.nativeapp.action.STOP_SCREEN_SHARE"
        const val EXTRA_RESULT_CODE = "projection_result_code"
        const val EXTRA_RESULT_DATA = "projection_result_data"
        const val EXTRA_SESSION_ID = "approved_session_id"
        private const val CHANNEL_ID = "myra_screen_share"
        private const val REQUEST_STOP = 8121

        @Volatile
        var isRunning: Boolean = false
            private set

        fun start(context: Context, resultCode: Int, data: Intent, sessionId: String) {
            require(ScreenShareProtocol.isValidSessionId(sessionId))
            val intent = Intent(context, ScreenShareProjectionService::class.java)
                .setAction(ACTION_START)
                .putExtra(EXTRA_RESULT_CODE, resultCode)
                .putExtra(EXTRA_RESULT_DATA, data)
                .putExtra(EXTRA_SESSION_ID, sessionId)
            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: Context) {
            if (!isRunning) return
            val intent = Intent(context, ScreenShareProjectionService::class.java).setAction(ACTION_STOP)
            context.startService(intent)
        }
    }
}
