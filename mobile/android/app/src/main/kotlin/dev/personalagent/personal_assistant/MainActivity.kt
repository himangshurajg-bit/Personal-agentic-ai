package dev.personalagent.personal_assistant

import android.Manifest
import android.app.AlarmManager
import android.app.DownloadManager
import android.app.ActivityManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ClipDescription
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.drawable.Icon
import android.graphics.pdf.PdfRenderer
import android.graphics.Canvas
import android.media.MediaPlayer
import android.net.Uri
import android.net.wifi.WifiManager
import android.net.TrafficStats
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Environment
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.StatFs
import android.provider.OpenableColumns
import android.provider.Settings
import android.speech.SpeechRecognizer
import android.speech.RecognitionListener
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.util.Base64
import androidx.appcompat.app.AlertDialog
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import com.google.android.gms.tasks.Tasks
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.util.concurrent.TimeUnit

internal fun isValidTextSharePayload(title: String?, text: String?): Boolean =
    !title.isNullOrBlank() && title.length <= 80 && !text.isNullOrBlank() && text.length <= 10000

internal fun temporaryWindowBrightness(level: Int): Float? =
    level.takeIf { it in 0..255 }?.div(255f)

internal const val MAX_CLIPBOARD_PREVIEW_CHARS = 4000
internal data class ClipboardPreviewText(val text: String, val truncated: Boolean)

internal fun boundedClipboardPreview(text: CharSequence?): ClipboardPreviewText? {
    if (text == null || text.isEmpty()) return null
    val length = minOf(text.length, MAX_CLIPBOARD_PREVIEW_CHARS)
    return ClipboardPreviewText(
        text = text.subSequence(0, length).toString(),
        truncated = text.length > MAX_CLIPBOARD_PREVIEW_CHARS,
    )
}

internal fun canPostAssistantTaskNotification(sdk: Int, notificationsGranted: Boolean): Boolean =
    sdk < 33 || notificationsGranted

internal fun plainClipboardText(hasPlainTextMimeType: Boolean, text: CharSequence?): String? =
    if (hasPlainTextMimeType) text?.toString() else null

internal const val GOOGLE_AI_MODE_URL = "https://www.google.com/ai"

internal fun assistantTaskStatusLabel(status: String): String? = when (status) {
    "preparing" -> "Preparing your request"
    "waitingForReply" -> "Waiting for the selected AI"
    "workingOffline" -> "Running the on-device model"
    "receivingReply" -> "Receiving the reply"
    else -> null
}

class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val ACTION_TASK_VOICE_COMMAND = "dev.personalagent.personal_assistant.TASK_VOICE_COMMAND"
        private const val TASK_NOTIFICATION_CHANNEL = "assistant_task_progress"
        private const val TASK_NOTIFICATION_ID = 6107
    }

    private var pendingTaskVoiceCommand = false
    private var taskTrackerChannel: MethodChannel? = null
    private var activeTaskNotificationId: String? = null
    private var hasTemporaryWindowBrightness = false
    private var originalWindowBrightness = android.view.WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE

    override fun onCreate(savedInstanceState: Bundle?) {
        if (intent?.action == ACTION_TASK_VOICE_COMMAND) pendingTaskVoiceCommand = true
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.action == ACTION_TASK_VOICE_COMMAND) {
            pendingTaskVoiceCommand = true
            taskTrackerChannel?.invokeMethod("voice_command_requested", null)
        }
    }

    // Activity context is not attached during construction. Defer packageName and
    // ComponentName lookups until the first MethodChannel request after attachment.
    private val launcherIconAliases: Map<String, ComponentName> by lazy {
        buildMap {
            (1..9).forEach { index ->
                put("nexa_$index", ComponentName(this@MainActivity, "$packageName.LauncherNexa$index"))
            }
            val addedIcons = listOf(
                "hrg_1", "novyra", "auralis", "orvexa", "zyntra", "veyra_ai",
                "parag_1", "paul_1", "adrit_1", "hemanga_1", "kaushik_1",
                "hrg_2", "parag_2", "paul_2", "adrit_2", "hemanga_2", "kaushik_2",
            )
            addedIcons.forEachIndexed { offset, iconId ->
                val aliasNumber = offset + 10
                put(iconId, ComponentName(this@MainActivity, "$packageName.LauncherNexa$aliasNumber"))
            }
        }
    }

    private fun currentLauncherIcon(): String = launcherIconAliases.entries
        .firstOrNull { (_, component) ->
            when (packageManager.getComponentEnabledSetting(component)) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED -> false
                else -> component.className.endsWith(".LauncherNexa1")
            }
        }?.key ?: "nexa_1"

    private fun setLauncherIcon(iconId: String) {
        val selected = launcherIconAliases[iconId]
            ?: throw IllegalArgumentException("Unknown home-screen icon choice")
        val previous = launcherIconAliases[currentLauncherIcon()]
        try {
            // Enable the replacement before disabling the old alias so the launcher
            // never ends up with no entry. Final state has exactly one enabled alias.
            packageManager.setComponentEnabledSetting(
                selected,
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                PackageManager.DONT_KILL_APP,
            )
            launcherIconAliases.values.filter { it != selected }.forEach { component ->
                packageManager.setComponentEnabledSetting(
                    component,
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                    PackageManager.DONT_KILL_APP,
                )
            }
        } catch (error: Exception) {
            // Best-effort rollback if Android rejects a component-state change.
            launcherIconAliases.values.forEach { component ->
                try {
                    packageManager.setComponentEnabledSetting(
                        component,
                        if (component == previous) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                        else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                        PackageManager.DONT_KILL_APP,
                    )
                } catch (_: Exception) {
                    // Preserve the original failure for the caller.
                }
            }
            throw error
        }
    }
    private var permissionResult: MethodChannel.Result? = null
    private var pendingAction: Map<*, *>? = null
    private var exportResult: MethodChannel.Result? = null
    private var exportText: String? = null
    private var exportBytes: ByteArray? = null
    private var backupImportResult: MethodChannel.Result? = null
    private var voice: SpeechRecognizer? = null
    private var voiceChannel: MethodChannel? = null
    private var featureVoiceChannel: MethodChannel? = null
    private var activeVoiceChannel: MethodChannel? = null
    private var audioChannel: MethodChannel? = null
    private var audioPlayer: MediaPlayer? = null
    private var audioFile: java.io.File? = null
    private var audioStartResult: MethodChannel.Result? = null
    private var voicePermission: MethodChannel.Result? = null
    private var accessPermissionResult: MethodChannel.Result? = null
    private var accessPermissionKind: String? = null
    private var voiceArgs: Map<*,*>? = null
    private var liveStopReceiver: BroadcastReceiver? = null
    private fun voiceEvent(kind:String, value:Any? = null) { activeVoiceChannel?.invokeMethod("voice_event",mapOf("kind" to kind,"value" to value)) }
    private fun stopVoice() { voice?.cancel();voice?.destroy();voice=null;voiceEvent("stopped") }
    private fun stopAudio() {
        val pending = audioStartResult
        audioStartResult = null
        try { audioPlayer?.setOnPreparedListener(null); audioPlayer?.setOnCompletionListener(null); audioPlayer?.setOnErrorListener(null); audioPlayer?.release() } catch (_: Exception) {}
        audioPlayer = null
        try { audioFile?.delete() } catch (_: Exception) {}
        audioFile = null
        pending?.error("cancelled", "Audio playback stopped", null)
    }
    private fun playAudio(args: Map<*, *>, result: MethodChannel.Result) {
        stopAudio()
        val bytes = args["bytes"] as? ByteArray
        if (bytes == null || bytes.isEmpty() || bytes.size > 12_000_000) {
            result.error("invalid_audio", "Audio is missing or exceeds the playback limit", null); return
        }
        try {
            val file = java.io.File.createTempFile("assistant-voice-", ".mp3", cacheDir)
            file.writeBytes(bytes)
            val player = MediaPlayer()
            audioFile = file; audioPlayer = player; audioStartResult = result
            player.setOnPreparedListener { prepared ->
                if (audioPlayer !== prepared) return@setOnPreparedListener
                val pending = audioStartResult; audioStartResult = null
                try { prepared.start(); pending?.success(mapOf("started" to true)) }
                catch (_: Exception) { pending?.error("playback_failed", "Audio could not start", null); stopAudio() }
            }
            player.setOnCompletionListener {
                stopAudio()
                audioChannel?.invokeMethod("audio_event", mapOf("kind" to "completed"))
            }
            player.setOnErrorListener { _, _, _ ->
                val pending = audioStartResult; audioStartResult = null
                stopAudio()
                pending?.error("playback_failed", "Audio playback failed", null)
                audioChannel?.invokeMethod("audio_event", mapOf("kind" to "error"))
                true
            }
            player.setDataSource(file.absolutePath)
            player.prepareAsync()
        } catch (_: Exception) {
            stopAudio()
            result.error("playback_failed", "Audio could not be prepared", null)
        }
    }
    private fun startVoice(args:Map<*,*>, result:MethodChannel.Result) {
        activeVoiceChannel = if(args["feature_voice"]==true) featureVoiceChannel else voiceChannel
        val mode=args["mode"] as? String
        val locale=args["locale"] as? String
        if(mode !in setOf("offline","online") || locale !in setOf("as-IN","en-IN","hi-IN","hi-Latn-IN")) { result.error("invalid","Unsupported speech selection",null);return }
        if(mode=="online" && args["approved_online"]!=true) {result.error("approval","Review online audio processing first",null);return}
        if(mode=="offline" && (Build.VERSION.SDK_INT<33 || !SpeechRecognizer.isOnDeviceRecognitionAvailable(this))) {result.error("unavailable","Verified on-device language recognition requires Android 13+ and an installed on-device service. No online fallback.",null);return}
        if(mode=="online" && !SpeechRecognizer.isRecognitionAvailable(this)) {result.error("unavailable","No system recognition service. Type instead.",null);return}
        if(checkSelfPermission(Manifest.permission.RECORD_AUDIO)!=PackageManager.PERMISSION_GRANTED) {
            if(voicePermission!=null) {result.error("busy","A microphone permission request is open",null);return}
            voicePermission=result;voiceArgs=args;requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO),44);return
        }
        stopVoice()
        try {
            val recognizer=if(mode=="offline") SpeechRecognizer.createOnDeviceSpeechRecognizer(this) else SpeechRecognizer.createSpeechRecognizer(this)
            voice=recognizer
            recognizer.setRecognitionListener(object:RecognitionListener {
                override fun onReadyForSpeech(params:Bundle?) { voiceEvent("listening") }
                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB:Float) { voiceEvent("level",rmsdB.toDouble()) }
                override fun onBufferReceived(buffer:ByteArray?) {}
                override fun onEndOfSpeech() {voiceEvent("stopped")}
                override fun onError(error:Int) { voiceEvent("error","Speech service error $error. No fallback or automatic retry. Typing remains available.") }
                override fun onResults(results:Bundle?) { voiceEvent("text",results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull() ?: "");voiceEvent("stopped") }
                override fun onPartialResults(results:Bundle?) { voiceEvent("partial",results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull() ?: "") }
                override fun onEvent(eventType:Int,params:Bundle?) {}
            })
            val intent=Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {putExtra(RecognizerIntent.EXTRA_LANGUAGE,locale);putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL,RecognizerIntent.LANGUAGE_MODEL_FREE_FORM);putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS,true)}
            if(mode=="offline" && Build.VERSION.SDK_INT>=33) {
                recognizer.checkRecognitionSupport(intent,mainExecutor,object:RecognitionSupportCallback {
                    override fun onSupportResult(support:RecognitionSupport) {
                        if(voice!==recognizer) {result.error("cancelled","Speech cancelled",null);return}
                        if(!support.installedOnDeviceLanguages.any { it.replace('_','-').equals(locale,true) }) {stopVoice();result.error("unavailable","Selected on-device language is not installed. No model download or online fallback was made; type instead.",null);return}
                        try {recognizer.startListening(intent);result.success(mapOf("started" to true,"mode" to "offline"))} catch(_:Exception) {stopVoice();result.error("unavailable","On-device recognition could not start; no online fallback",null)}
                    }
                    override fun onError(error:Int) {stopVoice();result.error("unavailable","Cannot verify installed offline language ($error). Type instead; no online fallback.",null)}
                })
            } else {recognizer.startListening(intent);result.success(mapOf("started" to true,"mode" to "online"))}
        } catch(_:Exception) {stopVoice();result.error("unavailable","Speech could not start; typing remains available",null)}
    }
    private fun showAssistantTaskNotification(title: String, status: String) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (!canPostAssistantTaskNotification(
                Build.VERSION.SDK_INT,
                Build.VERSION.SDK_INT < 33 || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED,
            )) {
            return // No unsolicited permission prompt; the in-app busy state remains visible.
        }
        manager.createNotificationChannel(
            NotificationChannel(
                TASK_NOTIFICATION_CHANNEL,
                "Assistant task progress",
                NotificationManager.IMPORTANCE_LOW,
            ),
        )
        val openChat = PendingIntent.getActivity(
            this,
            TASK_NOTIFICATION_ID,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val openVoice = PendingIntent.getActivity(
            this,
            TASK_NOTIFICATION_ID + 1,
            Intent(this, MainActivity::class.java)
                .setAction(ACTION_TASK_VOICE_COMMAND)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val privateTitle = title.replace(Regex("[\\r\\n\\t]+"), " ").trim().take(100)
        val notification = android.app.Notification.Builder(this, TASK_NOTIFICATION_CHANNEL)
            .setSmallIcon(android.R.drawable.ic_popup_sync)
            .setContentTitle(if (privateTitle.isBlank()) "Assistant task" else privateTitle)
            .setContentText(status)
            .setStyle(android.app.Notification.BigTextStyle().bigText(status))
            .setPublicVersion(
                android.app.Notification.Builder(this, TASK_NOTIFICATION_CHANNEL)
                    .setSmallIcon(android.R.drawable.ic_popup_sync)
                    .setContentTitle("Personal AI")
                    .setContentText("An assistant task is in progress")
                    .build(),
            )
            .setVisibility(android.app.Notification.VISIBILITY_PRIVATE)
            .setCategory(android.app.Notification.CATEGORY_PROGRESS)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setProgress(0, 0, true)
            .setTimeoutAfter(5 * 60 * 1000L)
            .setContentIntent(openChat)
            .addAction(android.app.Notification.Action.Builder(android.R.drawable.ic_btn_speak_now, "Voice command", openVoice).build())
            .build()

        val islandPayload = if (BuildConfig.HYPEROS_ISLAND_OPT_IN) {
            buildHyperOsIslandPayload(
                buildOptIn = true,
                manufacturer = Build.MANUFACTURER,
                brand = Build.BRAND,
                islandSystemFeature = hasHyperOsIslandSystemFeature(),
                focusProtocolVersion = hyperOsFocusProtocolVersion(),
                standardTaskStatus = status,
            )
        } else {
            null
        }
        if (islandPayload != null) {
            // The regular notification remains the source of truth and fallback.
            // The vendor view receives only fixed, generic app/status strings.
            notification.extras.putString(HYPEROS_ISLAND_PARAM_EXTRA, islandPayload)
            notification.extras.putBundle(
                HYPEROS_ISLAND_PICS_EXTRA,
                Bundle().apply {
                    putParcelable(
                        HYPEROS_ISLAND_APP_ICON_KEY,
                        Icon.createWithResource(this@MainActivity, R.mipmap.ic_launcher),
                    )
                },
            )
        }
        manager.notify(TASK_NOTIFICATION_ID, notification)
    }

    private fun hasHyperOsIslandSystemFeature(): Boolean {
        if (Build.MANUFACTURER.lowercase() !in setOf("xiaomi", "redmi", "poco") &&
            Build.BRAND.lowercase() !in setOf("xiaomi", "redmi", "poco")
        ) return false
        return try {
            val properties = Class.forName("android.os.SystemProperties")
            val getBoolean = properties.getDeclaredMethod(
                "getBoolean",
                String::class.java,
                Boolean::class.javaPrimitiveType,
            )
            getBoolean.invoke(null, "persist.sys.feature.island", false) as? Boolean ?: false
        } catch (_: Exception) {
            false
        }
    }

    private fun hyperOsFocusProtocolVersion(): Int = try {
        Settings.System.getInt(contentResolver, "notification_focus_protocol", 0)
    } catch (_: Exception) {
        0
    }

    override fun onPause() {
        restoreTemporaryWindowBrightness()
        stopVoice()
        stopAudio()
        offlineModelCoordinator?.onAppPaused()
        super.onPause()
    }
    override fun onDestroy() {
        pendingTorchOffResult?.let {
            completeTorchOffFailure("Personal AI closed before Android confirmed the flashlight state; check it before trying again.")
        }
        restoreTemporaryWindowBrightness()
        stopVoice()
        stopAudio()
        liveStopReceiver?.let { receiver ->
            try { unregisterReceiver(receiver) } catch (_: Exception) {}
        }
        liveStopReceiver = null
        offlineModelCoordinator?.shutdown()
        offlineModelCoordinator = null
        super.onDestroy()
    }
    private var fileResult: MethodChannel.Result? = null
    private var cameraResult: MethodChannel.Result? = null
    private var localOcrInFlight = false
    private var fileForAi = false
    private var fileForOfficeDocx = false
    private var localMediaResult: MethodChannel.Result? = null
    private var pendingTorchOffResult: MethodChannel.Result? = null
    private var torchOffManager: CameraManager? = null
    private var torchOffCallback: CameraManager.TorchCallback? = null
    private var torchOffTimeout: Runnable? = null
    private val torchOffHandler by lazy { Handler(Looper.getMainLooper()) }
    private var localMediaKind: String? = null
    private var previousSystemCpuTicks: SystemCpuTicks? = null
    private var offlineModelCoordinator: Gemma4OfflineCoordinator? = null
    private var offlineModelEventSink: EventChannel.EventSink? = null
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        val stopReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == LiveConversationService.ACTION_STOP_REQUESTED) {
                    voiceEvent("live_stop_requested")
                }
            }
        }
        liveStopReceiver = stopReceiver
        val stopFilter = android.content.IntentFilter(LiveConversationService.ACTION_STOP_REQUESTED)
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(stopReceiver, stopFilter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(stopReceiver, stopFilter)
        }
        MethodChannel(engine.dartExecutor.binaryMessenger, "personal_assistant/live_conversation")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                            result.error("permission", "Allow microphone access before starting live conversation.", null)
                            return@setMethodCallHandler
                        }
                        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            result.error("notification_permission", "Allow notifications so the ongoing microphone session has a visible Stop control.", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val service = Intent(this, LiveConversationService::class.java).setAction(LiveConversationService.ACTION_START)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(service)
                            else startService(service)
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("service_start_failed", error.message ?: "Android could not start the microphone service.", null)
                        }
                    }
                    "stop" -> {
                        try {
                            stopService(Intent(this, LiveConversationService::class.java))
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("service_stop_failed", error.message ?: "Android could not stop the microphone service.", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        offlineModelCoordinator = Gemma4OfflineCoordinator(applicationContext) { event ->
            offlineModelEventSink?.success(event)
        }
        EventChannel(engine.dartExecutor.binaryMessenger, "personal_assistant/offline_model/events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    offlineModelEventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    offlineModelEventSink = null
                }
            })
        MethodChannel(engine.dartExecutor.binaryMessenger, "personal_assistant/offline_model")
            .setMethodCallHandler { call, result ->
                val offline = offlineModelCoordinator
                if (offline == null) {
                    result.error("unavailable", "Local model management is unavailable in this session.", null)
                    return@setMethodCallHandler
                }
                when (call.method) {
                    "status" -> result.success(offline.status())
                    "set_experimental_chat_enabled" -> {
                        offline.setExperimentalChatEnabled(call.argument<Boolean>("enabled") == true)
                        result.success(true)
                    }
                    "run_chat" -> {
                        val prompt = call.argument<String>("prompt")
                        if (prompt.isNullOrBlank()) {
                            result.error("invalid_prompt", "The local prompt is empty.", null)
                        } else {
                            offline.runChat(prompt, call.argument<Boolean>("experimental_opt_in") == true) { text, code, message ->
                                if (code == null) result.success(text)
                                else result.error(code, message ?: "Local generation failed; no online fallback was used.", null)
                            }
                        }
                    }
                    "cancel_chat" -> { offline.cancelChat(); result.success(true) }
                    "select_model" -> {
                        val modelId = call.argument<String>("model_id")
                        if (modelId.isNullOrBlank()) result.error("invalid_model", "Choose a supported local model.", null)
                        else { offline.selectModel(modelId); result.success(true) }
                    }
                    "download" -> { offline.startDownload(); result.success(true) }
                    "cancel_download" -> { offline.cancelDownload(); result.success(true) }
                    "remove_model" -> { offline.removeModel(); result.success(true) }
                    "load_for_screening" -> { offline.loadForScreening(); result.success(true) }
                    "run_qualification" -> {
                        val fixture = call.argument<String>("fixture_id")
                        if (fixture.isNullOrBlank()) {
                            result.error("invalid_fixture", "Choose a fixed screening prompt.", null)
                        } else {
                            offline.runQualification(fixture)
                            result.success(true)
                        }
                    }
                    "cancel_inference" -> { offline.cancelInference(); result.success(true) }
                    "unload_candidate" -> { offline.unloadCandidate(); result.success(true) }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(engine.dartExecutor.binaryMessenger, "personal_assistant/rust_search").setMethodCallHandler { call, result ->
            if (call.method != "search_chats") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val request = call.argument<String>("request")
            if (request.isNullOrEmpty() || request.toByteArray(Charsets.UTF_8).size > 9_000_000) {
                result.error("invalid_request", "Local search request is missing or too large.", null)
                return@setMethodCallHandler
            }
            try {
                result.success(RustLocalSearch.search(request))
            } catch (_: LinkageError) {
                result.error("rust_unavailable", "Native local search is unavailable in this build.", null)
            } catch (_: Exception) {
                result.error("search_failed", "Local search could not complete.", null)
            }
        }
        voiceChannel=MethodChannel(engine.dartExecutor.binaryMessenger,"personal_assistant/voice")
        featureVoiceChannel=MethodChannel(engine.dartExecutor.binaryMessenger,"personal_assistant/feature_voice")
        audioChannel=MethodChannel(engine.dartExecutor.binaryMessenger,"personal_assistant/audio")
        MethodChannel(engine.dartExecutor.binaryMessenger, "personal_assistant/clipboard_preview")
            .setMethodCallHandler { call, result ->
                if (call.method != "read_plain_text") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    val manager = getSystemService(Context.CLIPBOARD_SERVICE) as? android.content.ClipboardManager
                    val clip = manager?.primaryClip
                    val isPlainText = manager?.primaryClipDescription
                        ?.hasMimeType(ClipDescription.MIMETYPE_TEXT_PLAIN) == true
                    val text = clip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.text
                    result.success(plainClipboardText(isPlainText, text))
                } catch (error: Exception) {
                    result.error("clipboard_unavailable", error.message ?: "Clipboard text is unavailable.", null)
                }
            }
        audioChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "play_audio" -> playAudio(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>(), result)
                "stop_audio" -> { stopAudio(); result.success(true) }
                else -> result.notImplemented()
            }
        }
        taskTrackerChannel = MethodChannel(
            engine.dartExecutor.binaryMessenger,
            "personal_assistant/task_tracker",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                when (call.method) {
                    "consume_voice_command_request" -> {
                        val requested = pendingTaskVoiceCommand
                        pendingTaskVoiceCommand = false
                        result.success(requested)
                    }
                    "show_task", "update_task" -> {
                        val id = args["id"] as? String
                        val title = args["title"] as? String
                        val status = args["status"] as? String
                        val label = status?.let(::assistantTaskStatusLabel)
                        if (id.isNullOrBlank() || title.isNullOrBlank() || label == null) {
                            result.error("invalid_task", "Task progress details are invalid.", null)
                        } else if (call.method == "update_task" && activeTaskNotificationId != id) {
                            // A late status callback from a cancelled request cannot replace a newer task.
                            result.success(null)
                        } else {
                            activeTaskNotificationId = id
                            showAssistantTaskNotification(title, label)
                            result.success(null)
                        }
                    }
                    "dismiss_task" -> {
                        val id = args["id"] as? String
                        if (id != null && activeTaskNotificationId == id) {
                            activeTaskNotificationId = null
                            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                                .cancel(TASK_NOTIFICATION_ID)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(engine.dartExecutor.binaryMessenger, "personal_assistant/web_search")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "open_google_ai_mode" -> {
                        try {
                            startActivity(
                                Intent(Intent.ACTION_VIEW, Uri.parse(GOOGLE_AI_MODE_URL)),
                            )
                            result.success(true)
                        } catch (_: Exception) {
                            result.error(
                                "browser_unavailable",
                                "No browser or Google app can open Google AI Mode.",
                                null,
                            )
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(engine.dartExecutor.binaryMessenger, "personal_assistant/app_update").setMethodCallHandler { call, result ->
            when (call.method) {
                "get_installed_version" -> {
                    try {
                        val info = packageManager.getPackageInfo(packageName, 0)
                        result.success(mapOf(
                            "packageName" to packageName,
                            "versionName" to (info.versionName ?: ""),
                            "versionCode" to if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong(),
                        ))
                    } catch (_: Exception) {
                        result.error("version_unavailable", "Installed app version is unavailable", null)
                    }
                }
                "open_official_release_download" -> {
                    val rawUrl = call.argument<String>("url")
                    val uri = try { Uri.parse(rawUrl ?: "") } catch (_: Exception) { null }
                    val allowedPath = uri?.encodedPath?.matches(
                        Regex("^/himangshurajg-bit/Personal-agentic-ai/releases/download/v[0-9]+(?:\\.[0-9]+){2,4}-build[1-9][0-9]*/app-release\\.apk$")
                    ) == true
                    if (uri == null || uri.scheme != "https" || uri.encodedAuthority != "github.com" ||
                        uri.query != null ||
                        uri.fragment != null || !allowedPath) {
                        result.error("invalid_release_url", "Only the pinned official APK release can be opened", null)
                    } else {
                        try {
                            startActivity(Intent(Intent.ACTION_VIEW, uri))
                            result.success(true)
                        } catch (_: Exception) {
                            result.error("release_unavailable", "No browser can open the official release download", null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(engine.dartExecutor.binaryMessenger, "personal_assistant/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "get_launcher_icon" -> result.success(currentLauncherIcon())
                "set_launcher_icon" -> {
                    val iconId = call.argument<String>("icon_id")
                    if (iconId == null || iconId !in launcherIconAliases) {
                        result.error("invalid_icon", "Choose one of the bundled home-screen icons.", null)
                    } else {
                        try {
                            setLauncherIcon(iconId)
                            result.success(iconId)
                        } catch (error: Exception) {
                            result.error("launcher_icon_failed", "Android could not change the home-screen icon.", error.message)
                        }
                    }
                }
                "set_system_timer" -> {
                    val request = SystemClockTimerRequestParser.parse(
                        call.argument<Any>("seconds"),
                        call.argument<Any>("label"),
                    )
                    if (request == null) {
                        result.error("invalid_argument", "Use 1–86,400 whole seconds and a label up to 40 characters", null)
                    } else {
                        val intent = Intent(android.provider.AlarmClock.ACTION_SET_TIMER).apply {
                            putExtra(android.provider.AlarmClock.EXTRA_LENGTH, request.seconds)
                            if (request.label.isNotEmpty()) {
                                putExtra(android.provider.AlarmClock.EXTRA_MESSAGE, request.label)
                            }
                            // Keep the Clock UI visible; the user explicitly starts it there.
                            putExtra(android.provider.AlarmClock.EXTRA_SKIP_UI, false)
                        }
                        try {
                            startActivity(intent)
                            result.success(true)
                        } catch (_: android.content.ActivityNotFoundException) {
                            result.error("unavailable", "No Android Clock app can handle timer requests", null)
                        } catch (_: Exception) {
                            result.error("unavailable", "Android could not open the Clock timer screen", null)
                        }
                    }
                }
                "turn_torch_off" -> reviewTorchOff(result)
                "open_map_search" -> reviewAndOpenMapSearch(
                    call.argument<Any>("destination"),
                    result,
                )
                "open_whatsapp_draft" -> reviewAndOpenWhatsAppDraft(
                    call.argument<Any>("number"),
                    call.argument<Any>("message"),
                    result,
                )
                "read_wifi_status" -> {
                    try {
                        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                        if (wifi == null) result.error("unavailable", "Wi-Fi status is unavailable on this device.", null)
                        else result.success(mapOf("enabled" to wifi.isWifiEnabled))
                    } catch (_: SecurityException) {
                        result.error("unavailable", "Android did not allow reading Wi-Fi enabled state.", null)
                    } catch (_: Exception) {
                        result.error("unavailable", "Wi-Fi status is unavailable on this device.", null)
                    }
                }
                "open_wifi_settings" -> {
                    val primary = Intent(WifiActions.INTERNET_CONNECTIVITY_PANEL)
                    try {
                        startActivity(primary)
                        result.success(mapOf("opened" to true, "destination" to "connectivity_panel"))
                    } catch (_: android.content.ActivityNotFoundException) {
                        try {
                            startActivity(Intent(WifiActions.WIFI_SETTINGS))
                            result.success(mapOf("opened" to true, "destination" to "wifi_settings"))
                        } catch (_: Exception) {
                            result.error("unavailable", "Android could not open Wi-Fi settings.", null)
                        }
                    } catch (_: Exception) {
                        try {
                            startActivity(Intent(WifiActions.WIFI_SETTINGS))
                            result.success(mapOf("opened" to true, "destination" to "wifi_settings"))
                        } catch (_: Exception) {
                            result.error("unavailable", "Android could not open Wi-Fi settings.", null)
                        }
                    }
                }
                "read_system_metrics" -> result.success(readSystemMonitorMetrics())
                "read_device_status_snapshot" -> result.success(DeviceStatusSnapshot.read(applicationContext))
                "enqueue_user_download" -> enqueueUserDownload(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>(), result)
                "list_user_downloads" -> listUserDownloads(result)
                "remove_user_download" -> removeUserDownload(call.argument<Any>("id"), result)
                "open_user_download" -> openUserDownload(call.argument<Any>("id"), result)
                "extract_image_text_locally" -> extractImageTextLocally(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>(), result)
                "extract_pdf_text_locally" -> extractPdfTextLocally(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>(), result)
                "device_status" -> result.success(mapOf(
                    "sdk" to Build.VERSION.SDK_INT,
                    "microphone_granted" to (checkSelfPermission(Manifest.permission.RECORD_AUDIO)==PackageManager.PERMISSION_GRANTED),
                    "notifications_granted" to (Build.VERSION.SDK_INT<33 || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)==PackageManager.PERMISSION_GRANTED),
                    "on_device_recognizer" to (Build.VERSION.SDK_INT>=31 && SpeechRecognizer.isOnDeviceRecognitionAvailable(this)),
                    "system_recognizer" to SpeechRecognizer.isRecognitionAvailable(this)
                ))
                "request_access_permission" -> requestAccessPermission(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>(), result)
                "share_text" -> shareText(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>(), result)
                "set_temporary_brightness" -> setTemporaryWindowBrightness(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>(), result)
                "restore_temporary_brightness" -> { restoreTemporaryWindowBrightness(); result.success(true) }
                "read_clipboard_text_preview" -> readClipboardTextPreview(result)
                "voice_start" -> startVoice(call.arguments as? Map<*,*> ?: emptyMap<Any,Any>(),result)
                "voice_cancel" -> {stopVoice();result.success(true)}
                "list_launchable_apps" -> {
                    Thread {
                        val apps = try { launchableAppCatalog() }
                        catch (_: Exception) { null }
                        runOnUiThread {
                            if (apps == null) result.error("unavailable", "Installed apps could not be listed", null)
                            else result.success(apps)
                        }
                    }.start()
                }
                "execute" -> {
                    val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                    if (args["kind"] == "reminder" && Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        if(permissionResult != null) { result.error("busy", "A permission request is already open", null) }
                        else { permissionResult=result; pendingAction=args; requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 41) }
                    } else execute(args,result)
                }
                "open_local_media" -> {
                    val kind = call.argument<String>("kind")
                    if (kind !in setOf("pdf", "video", "audio")) {
                        result.error("invalid_argument", "Choose PDF, video, or audio", null)
                    } else if (localMediaResult != null) {
                        result.error("busy", "A local file selection is already open", null)
                    } else {
                        localMediaResult = result
                        localMediaKind = kind
                        try {
                            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = when (kind) {
                                    "pdf" -> "application/pdf"
                                    "video" -> "video/*"
                                    else -> "audio/*"
                                }
                                if (kind == "audio") putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                            }, 44)
                        } catch (_: Exception) {
                            localMediaResult = null
                            localMediaKind = null
                            result.error("unavailable", "Android could not open the local file picker", null)
                        }
                    }
                }
                "capture_photo" -> {
                    if (cameraResult != null) result.error("busy", "A camera capture is already open", null)
                    else {
                        cameraResult = result
                        try {
                            startActivityForResult(Intent(android.provider.MediaStore.ACTION_IMAGE_CAPTURE), 45)
                        } catch (_: Exception) {
                            cameraResult = null
                            result.error("unavailable", "No Android camera app is available", null)
                        }
                    }
                }
                "import_backup" -> {
                    if (backupImportResult != null) {
                        result.error("busy", "A backup selection is already open", null)
                    } else {
                        backupImportResult = result
                        try {
                            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "application/json"
                            }, 46)
                        } catch (_: Exception) {
                            backupImportResult = null
                            result.error("unavailable", "Android could not open the backup picker", null)
                        }
                    }
                }
                "pick_file" -> {
                    if(fileResult != null) result.error("busy","A selection is already open",null)
                    else {
                        fileResult=result
                        fileForAi=call.argument<Boolean>("ai_document")==true
                        fileForOfficeDocx=call.argument<Boolean>("office_docx")==true
                        val mimeTypes = arrayOf("text/plain","text/markdown","text/csv","application/json","application/pdf","image/png","image/jpeg","image/webp") + if(fileForOfficeDocx) arrayOf("application/vnd.openxmlformats-officedocument.wordprocessingml.document") else emptyArray()
                        try { startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply { addCategory(Intent.CATEGORY_OPENABLE); type="*/*"; putExtra(Intent.EXTRA_MIME_TYPES,mimeTypes) },43) }
                        catch(_:Exception) { fileResult=null;fileForAi=false;fileForOfficeDocx=false;result.error("unavailable","Document picker unavailable",null) }
                    }
                }
                "export" -> {
                    if(exportResult != null) { result.error("busy","An export is already open",null) }
                    else {
                        exportText=call.argument<String>("text"); exportBytes=null; exportResult=result
                        val mimeType = call.argument<String>("mime_type")?.takeIf { it in setOf("application/json", "text/csv") } ?: "application/json"
                        val filename = safeDocumentExportName(call.argument<String>("filename"), if (mimeType == "text/csv") ".csv" else ".json")
                        try { startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply { addCategory(Intent.CATEGORY_OPENABLE); type=mimeType; putExtra(Intent.EXTRA_TITLE,filename) },42) }
                        catch(_:Exception) { exportResult=null; exportText=null; result.error("unavailable","No document picker is available",null) }
                    }
                }
                "export_bytes" -> {
                    if(exportResult != null) { result.error("busy","An export is already open",null) }
                    else {
                        val bytes = call.argument<ByteArray>("bytes")
                        if (bytes == null || bytes.isEmpty() || bytes.size > 256 * 1024) {
                            result.error("invalid_argument","ZIP export must be between 1 byte and 256 KB",null)
                            return@setMethodCallHandler
                        }
                        exportText=null; exportBytes=bytes.copyOf(); exportResult=result
                        val filename = safeDocumentExportName(call.argument<String>("filename"), ".zip")
                        try { startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply { addCategory(Intent.CATEGORY_OPENABLE); type="application/zip"; putExtra(Intent.EXTRA_TITLE,filename) },42) }
                        catch(_:Exception) { exportResult=null; exportBytes=null; result.error("unavailable","No document picker is available",null) }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
    private fun downloadRefs() = getSharedPreferences("user_downloads", MODE_PRIVATE)
        .getStringSet("refs", emptySet()).orEmpty().mapNotNull(UserDownloadRef::decode)

    private fun saveDownloadRefs(refs: List<UserDownloadRef>) {
        getSharedPreferences("user_downloads", MODE_PRIVATE).edit()
            .putStringSet("refs", refs.takeLast(100).map(UserDownloadRef::encode).toSet()).apply()
    }

    private fun enqueueUserDownload(args: Map<*, *>, result: MethodChannel.Result) {
        val target = UserDownloadData.validate(args["url"] as? String)
        if (target == null) {
            result.error("invalid_url", "Enter one credential-free HTTP or HTTPS download URL.", null)
            return
        }
        val requestedName = UserDownloadData.safeFileName(args["file_name"] as? String, target.fileName)
        val safeName = UserDownloadData.uniqueFileName(
            requestedName,
            downloadRefs().map { it.fileName }.toSet(),
        )
        val manager = getSystemService(Context.DOWNLOAD_SERVICE) as? DownloadManager
        if (manager == null) {
            result.error("unavailable", "Android Download Manager is unavailable; nothing was started.", null)
            return
        }
        try {
            val request = DownloadManager.Request(Uri.parse(target.url))
                .setTitle(safeName)
                .setDescription("Saved to Personal AI's app downloads")
                .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                .setAllowedOverRoaming(false)
                .setAllowedOverMetered(true)
                .setDestinationInExternalFilesDir(this, Environment.DIRECTORY_DOWNLOADS, safeName)
            val id = manager.enqueue(request)
            val ref = UserDownloadRef(id, safeName)
            saveDownloadRefs((downloadRefs().filterNot { it.id == id } + ref))
            result.success(mapOf("id" to id, "file_name" to safeName, "location" to "app-specific downloads"))
        } catch (_: Exception) {
            result.error("enqueue_failed", "Android could not start this download.", null)
        }
    }

    private fun listUserDownloads(result: MethodChannel.Result) {
        val manager = getSystemService(Context.DOWNLOAD_SERVICE) as? DownloadManager
        if (manager == null) {
            result.error("unavailable", "Android Download Manager is unavailable.", null)
            return
        }
        val rows = downloadRefs().sortedByDescending { it.id }.map { ref ->
            val cursor = try { manager.query(DownloadManager.Query().setFilterById(ref.id)) } catch (_: Exception) { null }
            if (cursor == null) return@map mapOf<String, Any?>("id" to ref.id, "file_name" to ref.fileName, "status" to "unknown", "label" to "Status unavailable", "progress" to null, "can_open" to false)
            cursor.use {
                if (!it.moveToFirst()) return@use mapOf<String, Any?>("id" to ref.id, "file_name" to ref.fileName, "status" to "unknown", "label" to "Status unavailable", "progress" to null, "can_open" to false)
                val status = it.getInt(it.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
                val reason = it.getInt(it.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON))
                val downloaded = it.getLong(it.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
                val total = it.getLong(it.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
                val progress = UserDownloadData.progress(downloaded, total)
                val state = when (status) {
                    DownloadManager.STATUS_PENDING -> "pending"
                    DownloadManager.STATUS_RUNNING -> "running"
                    DownloadManager.STATUS_PAUSED -> "paused"
                    DownloadManager.STATUS_SUCCESSFUL -> "complete"
                    DownloadManager.STATUS_FAILED -> "failed"
                    else -> "unknown"
                }
                val label = when (state) {
                    "pending" -> "Waiting to download"
                    "running" -> progress?.let { value -> "Downloading · $value%" } ?: "Downloading"
                    "paused" -> "Paused by Android (reason $reason)"
                    "complete" -> "Downloaded to app storage"
                    "failed" -> "Download failed (reason $reason)"
                    else -> "Status unavailable"
                }
                mapOf<String, Any?>("id" to ref.id, "file_name" to ref.fileName, "status" to state, "label" to label, "progress" to progress, "can_open" to (state == "complete"))
            }
        }
        result.success(rows)
    }

    private fun removeUserDownload(rawId: Any?, result: MethodChannel.Result) {
        val id = (rawId as? Number)?.toLong()?.takeIf { it > 0 } ?: run {
            result.error("invalid_id", "Choose a download from this list.", null); return
        }
        if (downloadRefs().none { it.id == id }) {
            result.error("unknown_id", "This download is not in Personal AI's list.", null); return
        }
        val manager = getSystemService(Context.DOWNLOAD_SERVICE) as? DownloadManager
        if (manager == null) { result.error("unavailable", "Android Download Manager is unavailable.", null); return }
        try {
            if (manager.remove(id) <= 0) {
                result.error("remove_unconfirmed", "Android did not confirm that this download was removed.", null)
                return
            }
            saveDownloadRefs(downloadRefs().filterNot { it.id == id })
            result.success(true)
        } catch (_: Exception) {
            result.error("remove_failed", "Android could not remove this download.", null)
        }
    }

    private fun openUserDownload(rawId: Any?, result: MethodChannel.Result) {
        val id = (rawId as? Number)?.toLong()?.takeIf { it > 0 } ?: run {
            result.error("invalid_id", "Choose a download from this list.", null); return
        }
        if (downloadRefs().none { it.id == id }) {
            result.error("unknown_id", "This download is not in Personal AI's list.", null); return
        }
        val manager = getSystemService(Context.DOWNLOAD_SERVICE) as? DownloadManager
        if (manager == null) { result.error("unavailable", "Android Download Manager is unavailable.", null); return }
        try {
            val uri = manager.getUriForDownloadedFile(id)
            if (uri == null) { result.error("not_ready", "Android has not made this download available yet.", null); return }
            val mime = manager.getMimeTypeForDownloadedFile(id) ?: "application/octet-stream"
            val intent = Intent(Intent.ACTION_VIEW).setDataAndType(uri, mime).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            startActivity(intent)
            result.success(true)
        } catch (_: android.content.ActivityNotFoundException) {
            result.error("no_handler", "No installed app can open this downloaded file.", null)
        } catch (_: Exception) {
            result.error("open_failed", "Android could not open this download.", null)
        }
    }

    /** Run bundled, on-device Latin-script OCR over one explicitly selected image. */
    private fun extractImageTextLocally(args: Map<*, *>, result: MethodChannel.Result) {
        if (localOcrInFlight) {
            result.error("busy", "An image text extraction is already running", null)
            return
        }
        val bytes = args["image_bytes"] as? ByteArray
        val mime = args["mime"] as? String
        if (bytes == null || bytes.isEmpty() || bytes.size > MAX_LOCAL_OCR_BYTES ||
            mime == null || !supportsLocalOcrMime(mime)) {
            result.error("invalid_image", "Choose a JPEG, PNG or WebP image up to 12 MB", null)
            return
        }

        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            result.error("invalid_image", "The selected image could not be decoded", null)
            return
        }
        val options = BitmapFactory.Options().apply {
            inSampleSize = localOcrSampleSize(bounds.outWidth, bounds.outHeight)
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        val bitmap = try { BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options) }
        catch (_: Exception) { null }
        if (bitmap == null) {
            result.error("invalid_image", "The selected image could not be decoded", null)
            return
        }

        localOcrInFlight = true
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        try {
            recognizer.process(InputImage.fromBitmap(bitmap, 0))
                .addOnSuccessListener { recognized ->
                    result.success(boundedLocalOcrText(recognized.text))
                }
                .addOnFailureListener { error ->
                    result.error("ocr_failed", "On-device text extraction failed", error.javaClass.simpleName)
                }
                .addOnCompleteListener {
                    localOcrInFlight = false
                    recognizer.close()
                    if (!bitmap.isRecycled) bitmap.recycle()
                }
        } catch (error: Exception) {
            localOcrInFlight = false
            recognizer.close()
            if (!bitmap.isRecycled) bitmap.recycle()
            result.error("ocr_failed", "On-device text extraction could not start", error.javaClass.simpleName)
        }
    }

    /** Rasterize only the first bounded set of pages and OCR them on-device. */
    private fun extractPdfTextLocally(args: Map<*, *>, result: MethodChannel.Result) {
        if (localOcrInFlight) {
            result.error("busy", "A local text extraction is already running", null)
            return
        }
        val bytes = args["pdf_bytes"] as? ByteArray
        val mime = args["mime"] as? String
        if (bytes == null || bytes.isEmpty() || bytes.size > MAX_LOCAL_PDF_OCR_BYTES || mime != "application/pdf") {
            result.error("invalid_pdf", "Choose a non-empty PDF up to 12 MB", null)
            return
        }

        localOcrInFlight = true
        Thread({
            var temporary: java.io.File? = null
            var recognizer: com.google.mlkit.vision.text.TextRecognizer? = null
            try {
                temporary = java.io.File.createTempFile("selected-pdf-ocr-", ".pdf", cacheDir)
                temporary.writeBytes(bytes)
                val descriptor = ParcelFileDescriptor.open(temporary, ParcelFileDescriptor.MODE_READ_ONLY)
                val renderedText = StringBuilder()
                var pagesProcessed = 0
                var pageCount = 0
                var truncated = false
                descriptor.use { pfd ->
                    PdfRenderer(pfd).use { renderer ->
                        pageCount = renderer.pageCount
                        val pageLimit = localPdfOcrPageLimit(pageCount)
                        truncated = pageCount > pageLimit
                        recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
                        for (index in 0 until pageLimit) {
                            val page = renderer.openPage(index)
                            page.use {
                                val dimensions = localPdfOcrBitmapSize(page.width, page.height)
                                    ?: throw IllegalArgumentException("PDF page has invalid dimensions")
                                val bitmap = Bitmap.createBitmap(dimensions.first, dimensions.second, Bitmap.Config.ARGB_8888)
                                try {
                                    page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                                    val text = Tasks.await(
                                        recognizer!!.process(InputImage.fromBitmap(bitmap, 0)),
                                        15,
                                        TimeUnit.SECONDS,
                                    ).text
                                    val existingText = renderedText.toString()
                                    truncated = truncated || pdfPageTextWouldTruncate(existingText, index + 1, text)
                                    val combined = appendBoundedPdfPage(existingText, index + 1, text)
                                    renderedText.setLength(0)
                                    renderedText.append(combined)
                                    pagesProcessed++
                                    if (renderedText.length >= MAX_LOCAL_PDF_OCR_CHARS) {
                                        truncated = truncated || index + 1 < pageCount
                                        break
                                    }
                                } finally {
                                    if (!bitmap.isRecycled) bitmap.recycle()
                                }
                            }
                        }
                    }
                }
                runOnUiThread {
                    localOcrInFlight = false
                    result.success(mapOf(
                        "text" to renderedText.toString(),
                        "pages_processed" to pagesProcessed,
                        "page_count" to pageCount,
                        "truncated" to truncated,
                    ))
                }
            } catch (error: Exception) {
                runOnUiThread {
                    localOcrInFlight = false
                    result.error("pdf_ocr_failed", "The selected PDF could not be read locally", error.javaClass.simpleName)
                }
            } finally {
                recognizer?.close()
                temporary?.delete()
            }
        }, "local-pdf-ocr").start()
    }

    /** Read aggregate device metrics on demand; no polling or history is retained. */
    private fun readSystemMonitorMetrics(): Map<String, Any?> {
        val cpuNow = try {
            java.io.File("/proc/stat").bufferedReader().use { reader ->
                SystemMonitorMetrics.parseCpuTicks(reader.readLine().orEmpty())
            }
        } catch (_: Exception) {
            null
        }
        val cpuPercent = SystemMonitorMetrics.cpuPercent(previousSystemCpuTicks, cpuNow)
        previousSystemCpuTicks = cpuNow

        val memory = try {
            val info = ActivityManager.MemoryInfo()
            (getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(info)
            info.availMem.takeIf { it >= 0L } to info.totalMem.takeIf { it > 0L }
        } catch (_: Exception) {
            null to null
        }
        val storage = try {
            val stats = StatFs(filesDir.absolutePath)
            stats.availableBytes.takeIf { it >= 0L } to stats.totalBytes.takeIf { it > 0L }
        } catch (_: Exception) {
            null to null
        }
        val received = TrafficStats.getTotalRxBytes().takeIf { it >= 0L }
        val sent = TrafficStats.getTotalTxBytes().takeIf { it >= 0L }
        return mapOf(
            "cpu_percent" to cpuPercent,
            "memory_available_bytes" to memory.first,
            "memory_total_bytes" to memory.second,
            "storage_free_bytes" to storage.first,
            "storage_total_bytes" to storage.second,
            "network_received_bytes" to received,
            "network_sent_bytes" to sent,
        )
    }

    private fun reviewAndOpenWhatsAppDraft(number: Any?, message: Any?, result: MethodChannel.Result) {
        val request = WhatsAppDraftPolicy.parse(number, message)
        if (request == null) {
            result.error(
                "invalid_argument",
                "Enter one full international number (+ and country code) and a message up to 1,600 characters.",
                null,
            )
            return
        }
        var completed = false
        fun cancelled() {
            if (completed) return
            completed = true
            result.success(mapOf("result" to "cancelled", "sent" to false))
        }
        val dialog = AlertDialog.Builder(this)
            .setTitle("Review WhatsApp message")
            .setMessage("To: ${request.number}\n\n${request.message}\n\nPersonal AI will open WhatsApp with this exact draft. Nothing is sent here; you must review it and tap Send in WhatsApp.")
            .setNegativeButton("Cancel") { _, _ -> cancelled() }
            .setPositiveButton("Open WhatsApp") { _, _ ->
                if (completed) return@setPositiveButton
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(WhatsAppDraftPolicy.link(request)))
                    .setPackage("com.whatsapp")
                try {
                    startActivity(intent)
                    completed = true
                    result.success(mapOf("result" to "handoff_opened", "sent" to false))
                } catch (_: Exception) {
                    completed = true
                    result.error("unavailable", "WhatsApp could not open this link; nothing was sent.", null)
                }
            }
            .create()
        dialog.setOnCancelListener { cancelled() }
        dialog.show()
    }

    private fun reviewTorchOff(result: MethodChannel.Result) {
        if (pendingTorchOffResult != null) {
            result.error("busy", "A flashlight-off review is already open.", null)
            return
        }
        pendingTorchOffResult = result
        val dialog = AlertDialog.Builder(this)
            .setTitle("Turn flashlight off?")
            .setMessage("Personal AI will ask Android to turn off the phone's camera flash. Nothing changes unless you approve this step. Camera permission, if needed, is requested only after you approve.")
            .setNegativeButton("Cancel") { _, _ -> completeTorchOffCancelled() }
            .setPositiveButton("Turn off") { _, _ ->
                if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
                    if (permissionResult != null || accessPermissionResult != null || voicePermission != null) {
                        completeTorchOffFailure("Another Android permission request is already open; the flashlight was not changed.")
                    } else {
                        try {
                            requestPermissions(arrayOf(Manifest.permission.CAMERA), 47)
                        } catch (_: Exception) {
                            completeTorchOffFailure("Android could not request camera permission; the flashlight was not changed.")
                        }
                    }
                } else {
                    applyTorchOff()
                }
            }
            .create()
        dialog.setOnCancelListener { completeTorchOffCancelled() }
        dialog.show()
    }

    private fun findFlashCameraId(manager: CameraManager): String? {
        val candidates = try {
            manager.cameraIdList.mapNotNull { id ->
                val characteristics = manager.getCameraCharacteristics(id)
                val flash = characteristics.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
                val back = characteristics.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
                TorchCameraCandidate(id, flash, back)
            }
        } catch (_: Exception) {
            return null
        }
        return chooseTorchCamera(candidates)
    }

    private fun applyTorchOff() {
        val result = pendingTorchOffResult ?: return
        if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            completeTorchOffFailure("Camera permission is not available; the flashlight was not changed.")
            return
        }
        val manager = getSystemService(Context.CAMERA_SERVICE) as? CameraManager
        if (manager == null) {
            completeTorchOffFailure("Android's camera service is unavailable; flashlight state is unchanged or unknown.")
            return
        }
        val cameraId = findFlashCameraId(manager)
        if (cameraId == null) {
            completeTorchOffFailure("No available camera flash was found; its state could not be changed.")
            return
        }

        var commandIssued = false
        var lastObservedState: Boolean? = null
        val callback = object : CameraManager.TorchCallback() {
            override fun onTorchModeChanged(id: String, enabled: Boolean) {
                if (id != cameraId) return
                lastObservedState = enabled
                if (commandIssued && !enabled) completeTorchOffSuccess()
            }

            override fun onTorchModeUnavailable(id: String) {
                if (id == cameraId) completeTorchOffFailure("Android reports the camera flash is unavailable; off state was not confirmed.")
            }
        }
        torchOffManager = manager
        torchOffCallback = callback
        try {
            manager.registerTorchCallback(callback, torchOffHandler)
            val timeout = Runnable {
                completeTorchOffFailure("Android did not confirm the flashlight is off. Check its state before trying again.")
            }
            torchOffTimeout = timeout
            torchOffHandler.postDelayed(timeout, 3_000)
            manager.setTorchMode(cameraId, false)
            commandIssued = true
            if (lastObservedState == false) completeTorchOffSuccess()
        } catch (_: Exception) {
            completeTorchOffFailure("Android could not confirm the flashlight-off request. Check its state before trying again.")
        }
    }

    private fun stopTorchOffObservation() {
        torchOffTimeout?.let(torchOffHandler::removeCallbacks)
        torchOffTimeout = null
        val manager = torchOffManager
        val callback = torchOffCallback
        if (manager != null && callback != null) {
            try { manager.unregisterTorchCallback(callback) } catch (_: Exception) { }
        }
        torchOffManager = null
        torchOffCallback = null
    }

    private fun completeTorchOffSuccess() {
        val result = pendingTorchOffResult ?: return
        pendingTorchOffResult = null
        stopTorchOffObservation()
        result.success(mapOf("result" to "confirmed_off"))
    }

    private fun completeTorchOffCancelled() {
        val result = pendingTorchOffResult ?: return
        pendingTorchOffResult = null
        stopTorchOffObservation()
        result.success(mapOf("result" to "cancelled"))
    }

    private fun completeTorchOffFailure(message: String) {
        val result = pendingTorchOffResult ?: return
        pendingTorchOffResult = null
        stopTorchOffObservation()
        result.error("torch_off_unconfirmed", message, null)
    }

    private fun reviewAndOpenMapSearch(rawDestination: Any?, result: MethodChannel.Result) {
        val request = MapSearchRequestParser.parse(rawDestination)
        if (request == null) {
            result.error("invalid_argument", "Enter one destination up to 120 characters", null)
            return
        }
        AlertDialog.Builder(this)
            .setTitle("Review Maps search")
            .setMessage("Open this exact destination in a map app?\n\n${request.destination}\n\nPersonal AI will not read your location or start navigation.")
            .setNegativeButton("Cancel") { _, _ ->
                result.success(mapOf("result" to "cancelled"))
            }
            .setPositiveButton("Open Maps search") { _, _ ->
                try {
                    startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(request.uri)))
                    result.success(mapOf("result" to "opened_search"))
                } catch (_: Exception) {
                    result.error("unavailable", "No map app could open this destination", null)
                }
            }
            .setOnCancelListener { result.success(mapOf("result" to "cancelled")) }
            .show()
    }

    private fun setTemporaryWindowBrightness(args: Map<*, *>, result: MethodChannel.Result) {
        val level = args["level"] as? Int
        val value = level?.let(::temporaryWindowBrightness)
        if (value == null) {
            result.error("invalid_argument", "Brightness must be an integer from 0 to 255", null)
            return
        }
        try {
            if (!hasTemporaryWindowBrightness) {
                originalWindowBrightness = window.attributes.screenBrightness
                hasTemporaryWindowBrightness = true
            }
            window.attributes = window.attributes.apply { screenBrightness = value }
            result.success(mapOf("applied" to level, "window_only" to true))
        } catch (_: Exception) {
            restoreTemporaryWindowBrightness()
            result.error("unavailable", "Android could not change this app window's brightness", null)
        }
    }

    private fun restoreTemporaryWindowBrightness() {
        if (!hasTemporaryWindowBrightness) return
        try {
            window.attributes = window.attributes.apply { screenBrightness = originalWindowBrightness }
        } catch (_: Exception) {
            // Best effort during lifecycle teardown; Android restores the window with the activity.
        } finally {
            hasTemporaryWindowBrightness = false
        }
    }

    private fun readClipboardTextPreview(result: MethodChannel.Result) {
        try {
            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
            val clip = clipboard?.primaryClip
            val firstPlainText = clip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.text
            val preview = boundedClipboardPreview(firstPlainText)
            if (preview == null) {
                result.error("no_plain_text", "The clipboard has no plain text to preview.", null)
                return
            }
            result.success(mapOf("text" to preview.text, "truncated" to preview.truncated))
        } catch (_: Exception) {
            result.error("unavailable", "Android could not read clipboard text.", null)
        }
    }
    private fun shareText(args: Map<*, *>, result: MethodChannel.Result) {
        val title = (args["title"] as? String)?.trim()
        val text = args["text"] as? String
        if (!isValidTextSharePayload(title, text)) {
            result.error("invalid_argument", "A short title and non-empty text up to 10,000 characters are required", null)
            return
        }
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
        }
        try {
            startActivity(Intent.createChooser(send, title))
            result.success(mapOf("result" to "chooser_opened", "sent" to false))
        } catch (_: Exception) {
            result.error("unavailable", "Android could not open the text share sheet", null)
        }
    }

    private fun safeDocumentExportName(requested: String?, extension: String): String {
        val name = (requested ?: "personal-data")
            .substringAfterLast('/')
            .substringAfterLast('\\')
            .replace(Regex("[^A-Za-z0-9._-]"), "_")
            .trim('.', '_')
            .take(80)
            .ifBlank { "personal-data" }
        val base = name.removeSuffix(".json").removeSuffix(".JSON")
            .removeSuffix(".csv").removeSuffix(".CSV")
            .removeSuffix(".zip").removeSuffix(".ZIP")
        return "$base$extension"
    }

    private fun cleanAppLabel(value: String): String =
        value.replace(Regex("[\\p{Cc}\\p{Cf}]"), " ")
            .replace(Regex("\\s+"), " ")
            .trim()
            .take(120)

    private fun launcherEntries(packageName: String? = null): List<ResolveInfo> {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        if (packageName != null) intent.setPackage(packageName)
        return packageManager.queryIntentActivities(intent, 0).filter { info ->
            val activity = info.activityInfo
            activity != null &&
                activity.packageName != this.packageName &&
                activity.enabled &&
                activity.applicationInfo.enabled
        }
    }

    private fun launchableAppCatalog(): List<Map<String, Any?>> {
        return launcherEntries()
            .groupBy { it.activityInfo.packageName }
            .mapNotNull { (appPackage, entries) ->
                val selected = entries
                    .mapNotNull { info ->
                        val label = cleanAppLabel(info.loadLabel(packageManager).toString())
                        if (label.isEmpty()) null else label to info
                    }
                    .minByOrNull { it.first.lowercase() }
                    ?: return@mapNotNull null
                val icon = try {
                    val drawable = selected.second.loadIcon(packageManager).mutate()
                    val bitmap = Bitmap.createBitmap(64, 64, Bitmap.Config.ARGB_8888)
                    val canvas = Canvas(bitmap)
                    drawable.setBounds(0, 0, 64, 64)
                    drawable.draw(canvas)
                    val bytes = ByteArrayOutputStream().use { stream ->
                        bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                        stream.toByteArray()
                    }
                    bitmap.recycle()
                    android.util.Base64.encodeToString(bytes, android.util.Base64.NO_WRAP)
                } catch (_: Exception) {
                    null
                }
                mapOf(
                    "package" to appPackage,
                    "label" to selected.first,
                    "icon_png_base64" to icon,
                )
            }
            .sortedWith(compareBy<Map<String, Any?>> { it["label"].toString().lowercase() }
                .thenBy { it["package"].toString() })
    }

    private fun execute(args:Map<*, *>,result:MethodChannel.Result) {
        try {
            when(args["kind"]) {
                "open_app" -> {
                    val packageName = args["package"] as? String
                        ?: throw IllegalArgumentException("Choose an app from the installed-app list")
                    val approvedLabel = args["app_name"] as? String
                        ?: throw IllegalArgumentException("The selected app name is missing")
                    val liveLabel = launcherEntries(packageName)
                        .mapNotNull { cleanAppLabel(it.loadLabel(packageManager).toString()).takeIf(String::isNotEmpty) }
                        .minByOrNull { it.lowercase() }
                        ?: throw IllegalStateException("That app is no longer launchable")
                    if (liveLabel != approvedLabel) {
                        throw IllegalStateException("The selected app changed; choose it again before approving")
                    }
                    val launch = packageManager.getLaunchIntentForPackage(packageName)
                        ?: throw IllegalStateException("That app is not installed or cannot be opened")
                    startActivity(launch)
                    result.success(mapOf("result" to "opened","detail" to "Android accepted the launch request for $liveLabel. Its screen was not independently checked."))
                }
                "reminder" -> {
                    val title=(args["title"] as? String)?.trim() ?: ""
                    val at=(args["at_ms"] as? Number)?.toLong() ?: 0L
                    val now=System.currentTimeMillis()
                    if(title.isEmpty() || title.length>120 || at<now+1000 || at>now+366L*86400000L) throw IllegalArgumentException("Reminder title or time is invalid")
                    if(Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED) {
                        result.success(mapOf("result" to "denied","detail" to "Notification permission denied; no reminder was scheduled.")); return
                    }
                    val prefs=getSharedPreferences("reminders",MODE_PRIVATE)
                    val id=prefs.getInt("next",100)+1
                    // Persist first: never report storage failure after scheduling an alarm.
                    if(!prefs.edit().putInt("next",id).putString("r$id",JSONObject().put("title",title).put("at",at).toString()).commit()) throw IllegalStateException("Could not persist reminder; no schedule was requested")
                    try { ReminderReceiver.schedule(this,id,title,at) }
                    catch(e:Exception) { prefs.edit().remove("r$id").commit(); result.success(mapOf("result" to "unknown","detail" to "Android scheduling did not return successfully; outcome is unverified. Do not repeat blindly.")); return }
                    result.success(mapOf("result" to "scheduled","detail" to "Android accepted the reminder schedule. Delivery is approximate and may be delayed by battery restrictions."))
                }
                else -> throw IllegalArgumentException("Unsupported action")
            }
        } catch(e:Exception) { result.success(mapOf("result" to "failed","detail" to (e.message ?: "Action failed; outcome not verified").take(300))) }
    }
    private fun requestAccessPermission(args: Map<*, *>, result: MethodChannel.Result) {
        val kind = args["permission"] as? String
        val permission = when (kind) {
            "microphone" -> Manifest.permission.RECORD_AUDIO
            "notifications" -> {
                if (Build.VERSION.SDK_INT < 33) {
                    result.success(mapOf("permission" to kind, "granted" to true, "required" to false))
                    return
                }
                Manifest.permission.POST_NOTIFICATIONS
            }
            else -> {
                result.error("invalid_permission", "Only microphone or notification access can be requested.", null)
                return
            }
        }
        if (checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) {
            result.success(mapOf("permission" to kind, "granted" to true, "required" to true))
            return
        }
        if (accessPermissionResult != null || permissionResult != null || voicePermission != null) {
            result.error("busy", "Another Android permission request is already open.", null)
            return
        }
        accessPermissionResult = result
        accessPermissionKind = kind
        requestPermissions(arrayOf(permission), 45)
    }

    override fun onRequestPermissionsResult(requestCode:Int,permissions:Array<out String>,grantResults:IntArray) {
        super.onRequestPermissionsResult(requestCode,permissions,grantResults)
        if (requestCode == 47) {
            val granted = checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
            if (granted) applyTorchOff()
            else completeTorchOffFailure("Camera permission was denied; the flashlight was not changed.")
        }
        if(requestCode==44) {
            val result=voicePermission;val args=voiceArgs;voicePermission=null;voiceArgs=null
            if(result!=null && args!=null) {
                if(grantResults.isNotEmpty() && grantResults[0]==PackageManager.PERMISSION_GRANTED) startVoice(args,result)
                else result.error("denied","Microphone permission denied. No audio was processed; typing still works.",null)
            }
        }
        if(requestCode==45) {
            val result=accessPermissionResult
            val kind=accessPermissionKind
            accessPermissionResult=null
            accessPermissionKind=null
            if(result!=null && kind!=null) {
                val permission=if(kind=="microphone") Manifest.permission.RECORD_AUDIO else Manifest.permission.POST_NOTIFICATIONS
                result.success(mapOf(
                    "permission" to kind,
                    "granted" to (checkSelfPermission(permission)==PackageManager.PERMISSION_GRANTED),
                    "required" to true
                ))
            }
        }
        if(requestCode==41) {
            val result=permissionResult; val args=pendingAction; permissionResult=null; pendingAction=null
            if(result!=null && args!=null) {
                if(grantResults.isNotEmpty() && grantResults[0]==PackageManager.PERMISSION_GRANTED) execute(args,result)
                else result.success(mapOf("result" to "denied","detail" to "Notification permission denied; no reminder was scheduled."))
            }
        }
    }
    @Deprecated("Android activity result bridge for Flutter document export")
    override fun onActivityResult(requestCode:Int,resultCode:Int,data:Intent?) {
        super.onActivityResult(requestCode,resultCode,data)
        if (requestCode == 45) {
            val result = cameraResult
            cameraResult = null
            if (resultCode != RESULT_OK) {
                result?.error("cancelled", "No photo captured", null)
                return
            }
            val bitmap = data?.extras?.get("data") as? Bitmap
            if (bitmap == null) {
                result?.error("capture_failed", "The camera did not return a photo", null)
                return
            }
            try {
                val output = ByteArrayOutputStream()
                if (!bitmap.compress(Bitmap.CompressFormat.JPEG, 88, output)) {
                    throw IllegalStateException("Could not encode the camera photo")
                }
                val bytes = output.toByteArray()
                if (!isValidJpegCapture(bytes)) {
                    throw IllegalArgumentException("Camera photo is empty or exceeds the 2 MB limit")
                }
                result?.success(mapOf(
                    "name" to "Camera photo",
                    "mime" to "image/jpeg",
                    "content_base64" to Base64.encodeToString(bytes, Base64.NO_WRAP)
                ))
            } catch (e: Exception) {
                result?.error("capture_failed", e.message ?: "Could not read camera photo", null)
            } finally {
                if (!bitmap.isRecycled) bitmap.recycle()
            }
            return
        }
        if (requestCode == 46) {
            val result = backupImportResult
            backupImportResult = null
            val uri = data?.data
            if (resultCode != RESULT_OK || uri == null) {
                result?.error("cancelled", "No backup selected", null)
                return
            }
            try {
                val mime = contentResolver.getType(uri)
                if (mime != null && mime !in setOf("application/json", "text/json", "application/octet-stream")) {
                    throw IllegalArgumentException("Choose a JSON backup file")
                }
                val bytes = contentResolver.openInputStream(uri)?.use { input ->
                    val output = java.io.ByteArrayOutputStream()
                    val buffer = ByteArray(8192)
                    var total = 0
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        total += count
                        if (total > 2 * 1024 * 1024) throw IllegalArgumentException("Backup exceeds the 2 MB limit")
                        output.write(buffer, 0, count)
                    }
                    output.toByteArray()
                } ?: throw IllegalStateException("Could not read selected backup")
                if (bytes.isEmpty()) throw IllegalArgumentException("Selected backup is empty")
                val decoder = Charsets.UTF_8.newDecoder().onMalformedInput(java.nio.charset.CodingErrorAction.REPORT)
                val json = decoder.decode(java.nio.ByteBuffer.wrap(bytes)).toString()
                result?.success(json)
            } catch (error: Exception) {
                result?.error("read_failed", error.message ?: "Could not read selected backup", null)
            }
            return
        }
        if(requestCode==43) {
            val result=fileResult;fileResult=null
            val forAi=fileForAi;fileForAi=false
            val forOfficeDocx=fileForOfficeDocx;fileForOfficeDocx=false
            val uri=data?.data
            if(resultCode!=RESULT_OK || uri==null) {result?.error("cancelled","No file selected",null);return}
            try {
                val rawMime=contentResolver.getType(uri) ?: "application/octet-stream"
                var name="Selected file"
                contentResolver.query(uri,arrayOf(OpenableColumns.DISPLAY_NAME),null,null,null)?.use { cursor -> if(cursor.moveToFirst()) name=cursor.getString(0) ?: name }
                val docxMime="application/vnd.openxmlformats-officedocument.wordprocessingml.document"
                val mime=if(forOfficeDocx && name.endsWith(".docx",ignoreCase=true) && rawMime in setOf("application/octet-stream","application/zip",docxMime)) docxMime else rawMime
                val response=mutableMapOf<String,Any>("name" to name.take(200),"mime" to mime)
                if(forAi) {
                    val allowedAiMimes = setOf("application/pdf","image/jpeg","image/png","image/webp") + if(forOfficeDocx) setOf("application/vnd.openxmlformats-officedocument.wordprocessingml.document") else emptySet()
                    if(mime !in allowedAiMimes) throw IllegalArgumentException("Choose a PDF, supported image${if(forOfficeDocx) " or DOCX" else ""}")
                    val bytes=contentResolver.openInputStream(uri)?.use { input ->
                        val out=java.io.ByteArrayOutputStream();val buffer=ByteArray(8192);var total=0
                        while(true) {val n=input.read(buffer);if(n<0)break;total+=n;if(total>12*1024*1024)throw IllegalArgumentException("File exceeds the 12 MB AI feature limit");out.write(buffer,0,n)}
                        out.toByteArray()
                    } ?: throw IllegalStateException("Could not read selected file")
                    if(bytes.isEmpty()) throw IllegalArgumentException("Selected file is empty")
                    response["content_base64"]=Base64.encodeToString(bytes,Base64.NO_WRAP)
                } else if(mime=="application/pdf") {response["unsupported"]="PDF selected. Extraction and PDF/image inference are not available in this build; no content was sent."}
                else {
                    val limit=if(mime.startsWith("image/")) 2000000 else 200000
                    val bytes=contentResolver.openInputStream(uri)?.use { input ->
                        val out=java.io.ByteArrayOutputStream();val buffer=ByteArray(8192);var total=0
                        while(true) {val n=input.read(buffer);if(n<0)break;total+=n;if(total>limit)throw IllegalArgumentException("File exceeds local preview limit");out.write(buffer,0,n)}
                        out.toByteArray()
                    } ?: throw IllegalStateException("Could not read selected file")
                    if(mime in setOf("image/png","image/jpeg")) response["image_base64"]=Base64.encodeToString(bytes,Base64.NO_WRAP)
                    else if(mime.startsWith("text/") || mime=="application/json" || name.endsWith(".csv", ignoreCase=true)) {
                        val decoder=Charsets.UTF_8.newDecoder().onMalformedInput(java.nio.charset.CodingErrorAction.REPORT)
                        response["text"]=decoder.decode(java.nio.ByteBuffer.wrap(bytes)).toString()
                    } else response["unsupported"]="This file type has no local reader in this build. No content sent."
                }
                result?.success(response)
            } catch(e:Exception) {result?.error("read_failed",e.message ?: "Could not read file",null)}
        }
        if(requestCode==44) {
            val result = localMediaResult; localMediaResult = null
            val kind = localMediaKind; localMediaKind = null
            if(resultCode != RESULT_OK || data == null || kind == null) {
                result?.error("cancelled", "No local file selected", null)
                return
            }
            try {
                if (kind == "audio") {
                    val selected = linkedSetOf<Uri>()
                    data.clipData?.let { clip ->
                        for (index in 0 until clip.itemCount) clip.getItemAt(index).uri?.let(selected::add)
                    }
                    data.data?.let(selected::add)
                    val incoming = selected.mapIndexedNotNull { index, uri ->
                        val mime = contentResolver.getType(uri)?.lowercase(java.util.Locale.ROOT)
                            ?: return@mapIndexedNotNull null
                        if (!mime.startsWith("audio/")) return@mapIndexedNotNull null
                        val name = runCatching {
                            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                                if (cursor.moveToFirst()) cursor.getString(0) else null
                            }
                        }.getOrNull()?.takeIf { it.isNotBlank() } ?: "Audio file ${index + 1}"
                        LocalAudioQueueEntry(uri.toString(), name, mime)
                    }
                    val update = LocalAudioQueue.add(emptyList(), incoming)
                    if (update.entries.isEmpty()) throw IllegalArgumentException("Choose one or more supported audio files")
                    val audioUris = update.entries.map { Uri.parse(it.uriKey) }
                    val viewer = Intent(this, LocalAudioQueueActivity::class.java).apply {
                        putStringArrayListExtra(LocalAudioQueueActivity.EXTRA_URIS, ArrayList(audioUris.map(Uri::toString)))
                        putExtra(LocalAudioQueueActivity.EXTRA_IGNORED_COUNT, selected.size - incoming.size + update.ignoredCount)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        val clip = ClipData.newUri(contentResolver, "Local audio", audioUris.first())
                        audioUris.drop(1).forEach { clip.addItem(ClipData.Item(it)) }
                        clipData = clip
                    }
                    startActivity(viewer)
                    result?.success(mapOf("viewer_opened" to true, "shared_online" to false))
                } else {
                    val uri = data.data ?: throw IllegalArgumentException("No local file selected")
                    val mime = contentResolver.getType(uri) ?: "application/octet-stream"
                    val valid = if(kind == "pdf") mime == "application/pdf" else mime.startsWith("video/")
                    if(!valid) throw IllegalArgumentException(if(kind == "pdf") "Choose a PDF file" else "Choose a video file")
                    val viewer = Intent(this, LocalMediaActivity::class.java).apply {
                        setDataAndType(uri, mime)
                        putExtra(LocalMediaActivity.EXTRA_KIND, kind)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        clipData = ClipData.newUri(contentResolver, "Local media", uri)
                    }
                    startActivity(viewer)
                    result?.success(mapOf("viewer_opened" to true, "shared_online" to false))
                }
            } catch(e: Exception) {
                result?.error("viewer_unavailable", e.message ?: "No local viewer could be opened", null)
            }
            return
        }
        if(requestCode==42) {
            val result=exportResult; val text=exportText; val bytes=exportBytes
            exportResult=null; exportText=null; exportBytes=null
            if(resultCode!=RESULT_OK || data?.data==null || (text==null && bytes==null)) { result?.error("cancelled","Export cancelled; no file saved",null); return }
            try {
                contentResolver.openOutputStream(data.data!!,"wt")?.use { stream ->
                    if (bytes != null) stream.write(bytes) else stream.write(text!!.toByteArray(Charsets.UTF_8))
                    stream.flush()
                } ?: throw IllegalStateException("Could not open destination")
                result?.success(mapOf("saved" to true))
            } catch(_:Exception) { result?.error("write_failed","Local data export could not be saved",null) }
        }
    }
}
class ReminderReceiver : BroadcastReceiver() {
    companion object {
        fun schedule(context:Context,id:Int,title:String,at:Long) {
            val intent=Intent(context,ReminderReceiver::class.java).putExtra("id",id).putExtra("title",title)
            val pending=PendingIntent.getBroadcast(context,id,intent,PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val alarms=context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP,at,pending)
        }
    }
    override fun onReceive(context:Context,intent:Intent) {
        val prefs=context.getSharedPreferences("reminders",Context.MODE_PRIVATE)
        if(intent.action==Intent.ACTION_BOOT_COMPLETED) {
            prefs.all.filterKeys { it.startsWith("r") }.forEach { (key,value) ->
                try { val obj=JSONObject(value as String); val at=obj.getLong("at"); if(at>System.currentTimeMillis()) schedule(context,key.drop(1).toInt(),obj.getString("title"),at) else prefs.edit().remove(key).apply() } catch(_:Exception) { /* malformed saved reminder is not executed */ }
            }
            return
        }
        val id=intent.getIntExtra("id",0)
        val manager=context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(NotificationChannel("reminders","Your reminders",NotificationManager.IMPORTANCE_DEFAULT))
        if(Build.VERSION.SDK_INT < 33 || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)==PackageManager.PERMISSION_GRANTED) {
            val open=PendingIntent.getActivity(context,id,Intent(context,MainActivity::class.java),PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            val notification=android.app.Notification.Builder(context,"reminders").setSmallIcon(android.R.drawable.ic_dialog_info).setContentTitle("Your reminder").setContentText(intent.getStringExtra("title") ?: "Reminder").setContentIntent(open).setAutoCancel(true).build()
            manager.notify(id,notification)
        }
        prefs.edit().remove("r$id").apply()
    }
}
