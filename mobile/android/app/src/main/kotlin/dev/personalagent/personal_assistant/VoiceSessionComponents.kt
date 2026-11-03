package dev.personalagent.personal_assistant

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.app.SearchManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.os.Bundle
import java.text.Normalizer
import java.util.Locale

internal data class VoicePhoneAction(
    val id: String,
    val requiresApproval: Boolean,
    val requiredPermission: String?,
) {
    fun authorized(approved: Boolean, permissionGranted: Boolean): Boolean =
        (!requiresApproval || approved) && (requiredPermission == null || permissionGranted)
}

/** Single registry of native phone actions exposed to voice conversations. */
internal object ActionRegistry {
    val actions = mapOf(
        "launch_app" to VoicePhoneAction("launch_app", requiresApproval = true, requiredPermission = null),
        "web_search" to VoicePhoneAction("web_search", requiresApproval = true, requiredPermission = null),
        "prepare_message" to VoicePhoneAction("prepare_message", requiresApproval = true, requiredPermission = null),
        "read_notifications" to VoicePhoneAction("read_notifications", requiresApproval = true, requiredPermission = "notification_access"),
    )

    fun get(id: String?): VoicePhoneAction? = id?.let(actions::get)
}

internal class PermissionManager(private val context: Context) {
    fun hasMicrophone(): Boolean = context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    fun hasNotificationListener(): Boolean {
        val enabled = Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners") ?: return false
        return enabled.split(':').any { component -> component.substringBefore('/').equals(context.packageName, ignoreCase = true) }
    }

    fun hasNotificationsPermission(): Boolean = Build.VERSION.SDK_INT < 33 ||
        context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    fun canExecute(actionId: String, approved: Boolean): Boolean {
        val action = ActionRegistry.get(actionId) ?: return false
        val permissionGranted = when (action.requiredPermission) {
            "notification_access" -> hasNotificationListener()
            else -> true
        }
        return action.authorized(approved, permissionGranted)
    }

    fun openNotificationAccessSettings() {
        context.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}

internal data class LaunchableApp(val label: String, val packageName: String)

internal class AppLauncher(private val context: Context) {
    fun list(): List<LaunchableApp> {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        @Suppress("DEPRECATION")
        return context.packageManager.queryIntentActivities(intent, 0)
            .asSequence()
            .filter { it.activityInfo.packageName != context.packageName }
            .map { LaunchableApp(it.loadLabel(context.packageManager).toString(), it.activityInfo.packageName) }
            .distinctBy { it.packageName }
            .sortedBy { it.label.lowercase(Locale.ROOT) }
            .take(200)
            .toList()
    }

    fun launch(packageName: String): Boolean {
        return try {
            val app = list().firstOrNull { it.packageName == packageName } ?: return false
            val intent = context.packageManager.getLaunchIntentForPackage(app.packageName) ?: return false
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            true
        } catch (_: android.content.ActivityNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }

    /** Open a platform web-search intent; the query is never submitted silently by this app. */
    fun openWebSearch(query: String): Boolean {
        if (query.isBlank() || query.length > 2000) return false
        val intent = Intent(Intent.ACTION_WEB_SEARCH).apply {
            putExtra(SearchManager.QUERY, query)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
        return true
    }

    /** Open an SMS composer with a reviewed draft; Android's messaging app owns the send step. */
    fun openSmsDraft(recipient: String?, body: String): Boolean {
        if (body.isBlank() || body.length > 4000) return false
        val number = recipient?.trim()?.takeIf { it.matches(Regex("^[+0-9() .-]{3,40}$")) }
        val uri = if (number == null) Uri.parse("smsto:") else Uri.fromParts("smsto", number, null)
        val intent = Intent(Intent.ACTION_SENDTO, uri).apply {
            putExtra("sms_body", body)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
        return true
    }
}

internal data class PhoneActionResult(
    val ok: Boolean,
    val code: String,
    val message: String,
    val data: Any? = null,
)

internal class TaskExecutor(private val permissions: PermissionManager, private val apps: AppLauncher) {
    fun execute(
        actionId: String,
        packageName: String?,
        approved: Boolean,
        query: String? = null,
        recipient: String? = null,
        message: String? = null,
    ): PhoneActionResult {
        val action = ActionRegistry.get(actionId)
            ?: return PhoneActionResult(false, "unsupported", "This phone action is not supported.")
        if (!permissions.canExecute(actionId, approved)) {
            val reason = if (action.requiresApproval && !approved) "approval_required" else "permission_required"
            return PhoneActionResult(false, reason, "The action was not run; required approval or permission is missing.")
        }
        return when (actionId) {
            "launch_app" -> {
                val target = packageName?.takeIf { it.isNotBlank() }
                    ?: return PhoneActionResult(false, "invalid_target", "Choose an installed app first.")
                if (apps.launch(target)) PhoneActionResult(true, "launched", "The approved app was opened.")
                else PhoneActionResult(false, "app_unavailable", "That app is not available in the launcher.")
            }
            "web_search" -> {
                val search = query?.trim()?.takeIf { it.isNotEmpty() && it.length <= 2000 }
                    ?: return PhoneActionResult(false, "invalid_query", "Provide a search query up to 2,000 characters.")
                try {
                    if (apps.openWebSearch(search)) PhoneActionResult(true, "search_opened", "Android opened the approved web search; no result was verified.")
                    else PhoneActionResult(false, "invalid_query", "Provide a non-empty search query.")
                } catch (_: android.content.ActivityNotFoundException) {
                    PhoneActionResult(false, "search_unavailable", "No Android app handles web search on this device.")
                } catch (_: SecurityException) {
                    PhoneActionResult(false, "search_unavailable", "Android could not open the web search.")
                }
            }
            "prepare_message" -> {
                val draft = message?.trim()?.takeIf { it.isNotEmpty() && it.length <= 4000 }
                    ?: return PhoneActionResult(false, "invalid_message", "Provide a message up to 4,000 characters.")
                try {
                    apps.openSmsDraft(recipient, draft)
                    PhoneActionResult(true, "draft_opened", "The reviewed draft opened in Android messaging; it was not sent.")
                } catch (_: android.content.ActivityNotFoundException) {
                    PhoneActionResult(false, "messaging_unavailable", "No Android messaging app handles SMS drafts on this device.")
                } catch (_: SecurityException) {
                    PhoneActionResult(false, "messaging_unavailable", "Android could not open the messaging app.")
                }
            }
            "read_notifications" -> {
                val notifications = NotificationReaderService.readActiveNotifications()
                    ?: return PhoneActionResult(false, "permission_required", "Enable notification access in Android settings first.")
                PhoneActionResult(true, "read", "The approved notification read completed.", notifications)
            }
            else -> PhoneActionResult(false, "unsupported", "This phone action is not supported.")
        }
    }
}

/** Invalidates callbacks delivered by recognizers that were stopped or replaced. */
internal class RecognitionEpoch {
    private var generation = 0L

    fun next(): Long = ++generation
    fun isCurrent(candidate: Long): Boolean = candidate == generation
    fun invalidate() { generation++ }
}

/** On-device-only wake phrase detection. It runs only after the user starts a visible voice session. */
internal class WakeWordManager(
    private val context: Context,
    private val onWakeWord: (String) -> Unit,
    private val onError: (String) -> Unit,
) {
    private val handler = Handler(Looper.getMainLooper())
    private var recognizer: SpeechRecognizer? = null
    private val recognizerEpoch = RecognitionEpoch()
    private var active = false
    private var locale = "en-IN"
    private var phrase = "hey personal ai"
    private var consecutiveErrors = 0

    fun start(locale: String, phrase: String = "hey personal ai"): Boolean {
        stop()
        if (Build.VERSION.SDK_INT < 31 || !SpeechRecognizer.isOnDeviceRecognitionAvailable(context)) {
            onError("Local wake-word listening requires Android 12+ and an available on-device speech service. No online fallback was used.")
            return false
        }
        if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            onError("Allow microphone access before starting local wake-word listening.")
            return false
        }
        this.locale = locale
        this.phrase = normalizeWakePhrase(phrase)
        active = true
        startRecognizer()
        return active
    }

    fun stop() {
        active = false
        handler.removeCallbacksAndMessages(null)
        releaseRecognizer()
    }

    /** Clear identity and invalidate callbacks before cancel(), which may itself callback. */
    private fun releaseRecognizer() {
        recognizerEpoch.invalidate()
        val previous = recognizer
        recognizer = null
        previous?.cancel()
        previous?.destroy()
    }

    private fun isCurrent(instance: SpeechRecognizer, generation: Long): Boolean =
        active && recognizer === instance && recognizerEpoch.isCurrent(generation)

    private fun startRecognizer() {
        if (!active) return
        releaseRecognizer()
        if (!active) return
        try {
            val generation = recognizerEpoch.next()
            val instance = SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
            recognizer = instance
            instance.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) = Unit
                override fun onBeginningOfSpeech() {
                    if (isCurrent(instance, generation)) consecutiveErrors = 0
                }
                override fun onRmsChanged(rmsdB: Float) = Unit
                override fun onBufferReceived(buffer: ByteArray?) = Unit
                override fun onEndOfSpeech() {
                    if (isCurrent(instance, generation)) scheduleRestart()
                }
                override fun onError(error: Int) {
                    if (isCurrent(instance, generation)) scheduleRestart(error)
                }
                override fun onResults(results: Bundle?) {
                    if (!isCurrent(instance, generation)) return
                    inspect(results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION))
                    scheduleRestart()
                }
                override fun onPartialResults(partialResults: Bundle?) {
                    if (isCurrent(instance, generation)) {
                        inspect(partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION))
                    }
                }
                override fun onEvent(eventType: Int, params: Bundle?) = Unit
            })
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
            }
            instance.startListening(intent)
        } catch (_: Exception) {
            active = false
            stop()
            onError("Local wake-word recognition could not start. No online fallback was used.")
        }
    }

    private fun inspect(results: List<String>?) {
        if (!active) return
        val match = results.orEmpty().firstOrNull { containsWakePhrase(it, phrase) } ?: return
        active = false
        releaseRecognizer()
        handler.removeCallbacksAndMessages(null)
        onWakeWord(match)
    }

    private fun scheduleRestart(error: Int? = null) {
        if (!active) return
        if (error != null && error != SpeechRecognizer.ERROR_NO_MATCH && error != SpeechRecognizer.ERROR_SPEECH_TIMEOUT) {
            consecutiveErrors += 1
            if (consecutiveErrors >= 8) {
                active = false
                stop()
                onError("Local wake-word recognition stopped after repeated device errors. No online fallback was used.")
                return
            }
        }
        handler.removeCallbacksAndMessages(null)
        val delay = if (error == null || error == SpeechRecognizer.ERROR_NO_MATCH || error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT) {
            350L
        } else {
            (500L shl (consecutiveErrors - 1).coerceAtMost(3)).coerceAtMost(4000L)
        }
        handler.postDelayed({ if (active) startRecognizer() }, delay)
    }
}

internal fun normalizeWakePhrase(value: String): String = Normalizer.normalize(value, Normalizer.Form.NFKC)
    .lowercase(Locale.ROOT)
    .replace(Regex("[^\\p{L}\\p{N}]+"), " ")
    .trim()

internal fun containsWakePhrase(recognized: String, phrase: String): Boolean {
    val normalizedText = normalizeWakePhrase(recognized)
    val normalizedPhrase = normalizeWakePhrase(phrase)
    return normalizedPhrase.isNotBlank() && (normalizedText == normalizedPhrase || normalizedText.startsWith("$normalizedPhrase "))
}
