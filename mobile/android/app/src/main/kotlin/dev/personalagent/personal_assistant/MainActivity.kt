package dev.personalagent.personal_assistant

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.speech.SpeechRecognizer
import android.speech.RecognitionListener
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.util.Base64
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import org.json.JSONObject
import java.io.ByteArrayOutputStream

internal fun isValidTextSharePayload(title: String?, text: String?): Boolean =
    !title.isNullOrBlank() && title.length <= 80 && !text.isNullOrBlank() && text.length <= 10000

class MainActivity : FlutterFragmentActivity() {
    // Activity context is not attached during construction. Defer packageName and
    // ComponentName lookups until the first MethodChannel request after attachment.
    private val launcherIconAliases: Map<String, ComponentName> by lazy {
        (1..9).associate { index ->
            "nexa_$index" to ComponentName(this, "$packageName.LauncherNexa$index")
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
    private var voice: SpeechRecognizer? = null
    private var voiceChannel: MethodChannel? = null
    private var audioChannel: MethodChannel? = null
    private var audioPlayer: MediaPlayer? = null
    private var audioFile: java.io.File? = null
    private var audioStartResult: MethodChannel.Result? = null
    private var voicePermission: MethodChannel.Result? = null
    private var accessPermissionResult: MethodChannel.Result? = null
    private var accessPermissionKind: String? = null
    private var voiceArgs: Map<*,*>? = null
    private fun voiceEvent(kind:String, value:Any? = null) { voiceChannel?.invokeMethod("voice_event",mapOf("kind" to kind,"value" to value)) }
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
    override fun onPause() {
        stopVoice()
        stopAudio()
        offlineModelCoordinator?.onAppPaused()
        super.onPause()
    }
    override fun onDestroy() {
        stopVoice()
        stopAudio()
        offlineModelCoordinator?.shutdown()
        offlineModelCoordinator = null
        super.onDestroy()
    }
    private var fileResult: MethodChannel.Result? = null
    private var offlineModelCoordinator: Gemma4OfflineCoordinator? = null
    private var offlineModelEventSink: EventChannel.EventSink? = null
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
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
        audioChannel=MethodChannel(engine.dartExecutor.binaryMessenger,"personal_assistant/audio")
        audioChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "play_audio" -> playAudio(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>(), result)
                "stop_audio" -> { stopAudio(); result.success(true) }
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
                "device_status" -> result.success(mapOf(
                    "sdk" to Build.VERSION.SDK_INT,
                    "microphone_granted" to (checkSelfPermission(Manifest.permission.RECORD_AUDIO)==PackageManager.PERMISSION_GRANTED),
                    "notifications_granted" to (Build.VERSION.SDK_INT<33 || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)==PackageManager.PERMISSION_GRANTED),
                    "on_device_recognizer" to (Build.VERSION.SDK_INT>=31 && SpeechRecognizer.isOnDeviceRecognitionAvailable(this)),
                    "system_recognizer" to SpeechRecognizer.isRecognitionAvailable(this)
                ))
                "request_access_permission" -> requestAccessPermission(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>(), result)
                "share_text" -> shareText(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>(), result)
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
                "pick_file" -> {
                    if(fileResult != null) result.error("busy","A selection is already open",null)
                    else {
                        fileResult=result
                        try { startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply { addCategory(Intent.CATEGORY_OPENABLE); type="*/*"; putExtra(Intent.EXTRA_MIME_TYPES,arrayOf("text/plain","text/markdown","application/json","application/pdf","image/png","image/jpeg")) },43) }
                        catch(_:Exception) { fileResult=null;result.error("unavailable","Document picker unavailable",null) }
                    }
                }
                "export" -> {
                    if(exportResult != null) { result.error("busy","An export is already open",null) }
                    else {
                        exportText=call.argument<String>("text"); exportResult=result
                        val filename = safeJsonExportName(call.argument<String>("filename"))
                        try { startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply { addCategory(Intent.CATEGORY_OPENABLE); type="application/json"; putExtra(Intent.EXTRA_TITLE,filename) },42) }
                        catch(_:Exception) { exportResult=null; exportText=null; result.error("unavailable","No document picker is available",null) }
                    }
                }
                else -> result.notImplemented()
            }
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

    private fun safeJsonExportName(requested: String?): String {
        val name = (requested ?: "personal-memories.json")
            .substringAfterLast('/')
            .substringAfterLast('\\')
            .replace(Regex("[^A-Za-z0-9._-]"), "_")
            .trim('.', '_')
            .take(80)
            .ifBlank { "personal-data" }
        return if (name.endsWith(".json", ignoreCase = true)) name else "$name.json"
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
        if(requestCode==43) {
            val result=fileResult;fileResult=null
            val uri=data?.data
            if(resultCode!=RESULT_OK || uri==null) {result?.error("cancelled","No file selected",null);return}
            try {
                val mime=contentResolver.getType(uri) ?: "application/octet-stream"
                var name="Selected file"
                contentResolver.query(uri,arrayOf(OpenableColumns.DISPLAY_NAME),null,null,null)?.use { cursor -> if(cursor.moveToFirst()) name=cursor.getString(0) ?: name }
                val response=mutableMapOf<String,Any>("name" to name.take(200),"mime" to mime)
                if(mime=="application/pdf") {response["unsupported"]="PDF selected. Extraction and PDF/image inference are not available in this build; no content was sent."}
                else {
                    val limit=if(mime.startsWith("image/")) 2000000 else 200000
                    val bytes=contentResolver.openInputStream(uri)?.use { input ->
                        val out=java.io.ByteArrayOutputStream();val buffer=ByteArray(8192);var total=0
                        while(true) {val n=input.read(buffer);if(n<0)break;total+=n;if(total>limit)throw IllegalArgumentException("File exceeds local preview limit");out.write(buffer,0,n)}
                        out.toByteArray()
                    } ?: throw IllegalStateException("Could not read selected file")
                    if(mime in setOf("image/png","image/jpeg")) response["image_base64"]=Base64.encodeToString(bytes,Base64.NO_WRAP)
                    else if(mime.startsWith("text/") || mime=="application/json") {
                        val decoder=Charsets.UTF_8.newDecoder().onMalformedInput(java.nio.charset.CodingErrorAction.REPORT)
                        response["text"]=decoder.decode(java.nio.ByteBuffer.wrap(bytes)).toString()
                    } else response["unsupported"]="This file type has no local reader in this build. No content sent."
                }
                result?.success(response)
            } catch(e:Exception) {result?.error("read_failed",e.message ?: "Could not read file",null)}
        }
        if(requestCode==42) {
            val result=exportResult; val text=exportText; exportResult=null; exportText=null
            if(resultCode!=RESULT_OK || data?.data==null || text==null) { result?.error("cancelled","Export cancelled; no file saved",null); return }
            try { contentResolver.openOutputStream(data.data!!,"wt")?.use { it.write(text.toByteArray(Charsets.UTF_8)); it.flush() } ?: throw IllegalStateException("Could not open destination")
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
