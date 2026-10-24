package dev.personalagent.personal_assistant

import android.app.ActivityManager
import android.content.Context
import android.os.Debug
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.StatFs
import android.os.SystemClock
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Conversation
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

internal data class OfflineModelArtifact(
    val modelId: String,
    val displayName: String,
    val modelFile: String,
    val modelBytes: Long,
    val sha256: String,
    val revision: String,
    val url: String,
    val license: String,
    val minimumMemoryGb: Int?,
    val description: String,
) {
    val partialFile: String get() = "$modelFile.part"

    fun allowsRedirect(uri: URI): Boolean {
        if (!uri.scheme.equals("https", ignoreCase = true) || uri.userInfo != null) return false
        val host = uri.host?.lowercase(Locale.ROOT) ?: return false
        return host == "huggingface.co" || host.endsWith(".huggingface.co") || host.endsWith(".hf.co")
    }
}

internal object Gemma4Artifact {
    const val MODEL_ID = "gemma-4-E2B-it"
    const val MODEL_FILE = "gemma-4-E2B-it.litertlm"
    const val PART_FILE = "$MODEL_FILE.part"
    const val PREVIOUS_MODEL_FILE = "gemma-4-E4B-it.litertlm"
    const val PREVIOUS_PART_FILE = "$PREVIOUS_MODEL_FILE.part"
    const val MODEL_BYTES = 2_588_147_712L
    const val SHA256 = "181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c"
    const val REVISION = "6e5c4f1e395deb959c494953478fa5cec4b8008f"
    const val URL = "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/$REVISION/$MODEL_FILE"
    const val LITERT_LM_VERSION = "0.18.1"
    const val MIN_DEVICE_MEMORY_GB = 8
    const val LICENSE = "Apache-2.0"
    const val SAFETY_RESERVE_BYTES = 512L * 1024L * 1024L

    fun allowsRedirect(uri: URI): Boolean {
        if (!uri.scheme.equals("https", ignoreCase = true) || uri.userInfo != null) return false
        val host = uri.host?.lowercase(Locale.ROOT) ?: return false
        return host == "huggingface.co" || host.endsWith(".huggingface.co") || host.endsWith(".hf.co")
    }
}

internal object OfflineModelArtifacts {
    val gemma4 = OfflineModelArtifact(
        modelId = Gemma4Artifact.MODEL_ID,
        displayName = "Gemma 4 E2B",
        modelFile = Gemma4Artifact.MODEL_FILE,
        modelBytes = Gemma4Artifact.MODEL_BYTES,
        sha256 = Gemma4Artifact.SHA256,
        revision = Gemma4Artifact.REVISION,
        url = Gemma4Artifact.URL,
        license = Gemma4Artifact.LICENSE,
        minimumMemoryGb = Gemma4Artifact.MIN_DEVICE_MEMORY_GB,
        description = "5.1B total · 2.3B effective parameters · 8 GB minimum listed",
    )
    val qwen3 = OfflineModelArtifact(
        modelId = "qwen3-0.6b",
        displayName = "Qwen3 0.6B",
        modelFile = "Qwen3-0.6B.litertlm",
        modelBytes = 613_722_264L,
        sha256 = "c5f39b4191926786c3e6668b62af4d6eb15248dfc7a5348252a9b406f33f2108",
        revision = "e6687177e00897731e7716267eebd4eba0dde7c2",
        url = "https://huggingface.co/litert-community/Qwen3-0.6B/resolve/e6687177e00897731e7716267eebd4eba0dde7c2/Qwen3-0.6B.litertlm",
        license = "Apache-2.0",
        minimumMemoryGb = null,
        description = "0.6B parameters · 614 MB download · no published device-memory minimum",
    )
    val all = listOf(gemma4, qwen3)
    fun find(modelId: String): OfflineModelArtifact? = all.firstOrNull { it.modelId == modelId }
}

internal data class ByteRange(val start: Long, val end: Long, val total: Long)

internal object Gemma4TransferPolicy {
    private val contentRangePattern = Regex("^bytes (\\d+)-(\\d+)/(\\d+)$", RegexOption.IGNORE_CASE)

    fun parseContentRange(value: String?): ByteRange? {
        val match = value?.trim()?.let(contentRangePattern::matchEntire) ?: return null
        val start = match.groupValues[1].toLongOrNull() ?: return null
        val end = match.groupValues[2].toLongOrNull() ?: return null
        val total = match.groupValues[3].toLongOrNull() ?: return null
        if (start > end || end >= total) return null
        return ByteRange(start, end, total)
    }

    fun resumeOffset(partialBytes: Long, expectedBytes: Long): Long? =
        if (partialBytes in 1 until expectedBytes) partialBytes else null

    fun hasEnoughSpace(availableBytes: Long, partialBytes: Long, expectedBytes: Long): Boolean {
        if (availableBytes < 0L || expectedBytes < 0L) return false
        val validPartialBytes = partialBytes.takeIf { it in 0L..expectedBytes } ?: 0L
        val remaining = expectedBytes - validPartialBytes
        return remaining <= availableBytes - Gemma4Artifact.SAFETY_RESERVE_BYTES
    }
}

internal object Gemma4FileIntegrity {
    fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered(1024 * 1024).use { input ->
            val buffer = ByteArray(1024 * 1024)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(Locale.ROOT, it.toInt() and 0xff) }
    }

    fun verify(file: File, expectedBytes: Long, expectedSha256: String): Boolean =
        file.isFile && file.length() == expectedBytes &&
            sha256(file).equals(expectedSha256, ignoreCase = true)

    fun installAtomically(part: File, destination: File, expectedBytes: Long, expectedSha256: String) {
        require(verify(part, expectedBytes, expectedSha256)) { "Model file did not match the pinned size and SHA-256." }
        Files.move(part.toPath(), destination.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
    }
}

internal data class QualificationPrompt(val id: String, val label: String, val text: String)

internal object Gemma4QualificationPrompts {
    val all = listOf(
        QualificationPrompt(
            "english",
            "English · Newton’s law",
            "For a Class 12/JEE learner, explain Newton’s second law in two or three short sentences. A 2 kg cart accelerates at 3 m/s². Use F = m × a, show the calculation and unit, and answer in English.",
        ),
        QualificationPrompt(
            "assamese",
            "Assamese · Newton’s law",
            "দ্বাদশ শ্ৰেণীৰ/JEE শিক্ষাৰ্থীৰ বাবে নিউটনৰ দ্বিতীয় নিয়মটো দুই-তিনিটা চুটি বাক্যত বুজাই দিয়া। 2 kg ভৰৰ এখন গাড়ীৰ ত্বৰণ 3 m/s²। F = m × a ব্যৱহাৰ কৰি গণনা আৰু একক দেখুওৱা, আৰু অসমীয়াত উত্তৰ দিয়া।",
        ),
        QualificationPrompt(
            "arithmetic",
            "Arithmetic · units",
            "Calculate 2 kg × 3 m/s². Show the multiplication, give the correct SI unit, and explain in one short sentence why the unit is a newton.",
        ),
        QualificationPrompt(
            "jee",
            "Class 12/JEE · tutoring",
            "A learner says a 2 kg cart accelerating at 3 m/s² experiences 20 N of force. Correct the mistake gently, show F = m × a and the unit, then explain the idea in two or three short sentences for a Class 12/JEE student.",
        ),
        QualificationPrompt(
            "hindi",
            "Hindi · Devanagari",
            "कक्षा 12/JEE के विद्यार्थी के लिए न्यूटन का दूसरा नियम दो या तीन छोटे वाक्यों में समझाइए। 2 kg की गाड़ी का त्वरण 3 m/s² है। F = m × a लगाकर गणना और इकाई दिखाइए और देवनागरी हिन्दी में उत्तर दीजिए।",
        ),
        QualificationPrompt(
            "hinglish",
            "Hinglish · Roman script",
            "Class 12/JEE student ko Newton’s second law 2–3 short sentences mein natural Hinglish mein samjhao. 2 kg ki cart 3 m/s² se accelerate karti hai. F = m × a lagao, calculation aur unit dikhao, aur Roman script mein jawab do.",
        ),
    )

    fun find(id: String): QualificationPrompt? = all.firstOrNull { it.id == id }
}

/**
 * User-started candidate download and isolated evaluation only. This class is deliberately not
 * connected to the normal assistant chat or its online provider paths.
 */
internal class Gemma4OfflineCoordinator(
    context: Context,
    private val publish: (Map<String, Any?>) -> Unit,
) {
    private val appContext = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private val downloadExecutor = Executors.newSingleThreadExecutor()
    private val downloadCancelled = AtomicBoolean(false)
    private val downloadConnection = AtomicReference<HttpURLConnection?>(null)
    @Volatile private var downloadActive = false
    @Volatile private var fileRemovalActive = false

    private val inferenceExecutor = Executors.newSingleThreadExecutor()
    private val inferenceDispatcher = inferenceExecutor.asCoroutineDispatcher()
    private val inferenceScope = CoroutineScope(SupervisorJob() + inferenceDispatcher)
    // Cancellation must not queue behind the single-threaded inference stream it is stopping.
    private val controlScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val runtimeMutex = Mutex()
    @Volatile private var engine: Engine? = null
    @Volatile private var activeConversation: Conversation? = null
    @Volatile private var inferenceActive = false
    @Volatile private var runtimeOperation = false
    @Volatile private var activePurpose: String? = null
    @Volatile private var inferenceCancelRequested = false
    @Volatile private var activeChatCancellation: AtomicBoolean? = null
    @Volatile private var experimentalChatEnabled = false
    private val disposed = AtomicBoolean(false)

    private val modelPreferences = appContext.getSharedPreferences("offline_model_selection", Context.MODE_PRIVATE)
    @Volatile private var selectedModelId: String = modelPreferences.getString("model_id", Gemma4Artifact.MODEL_ID)
        ?.takeIf { OfflineModelArtifacts.find(it) != null } ?: Gemma4Artifact.MODEL_ID
    private val selectedArtifact: OfflineModelArtifact
        get() = OfflineModelArtifacts.find(selectedModelId) ?: OfflineModelArtifacts.gemma4
    private val modelFile get() = File(appContext.filesDir, selectedArtifact.modelFile)
    private val partialFile get() = File(appContext.filesDir, selectedArtifact.partialFile)
    private val previousModelFile get() = File(appContext.filesDir, Gemma4Artifact.PREVIOUS_MODEL_FILE)
    private val previousPartialFile get() = File(appContext.filesDir, Gemma4Artifact.PREVIOUS_PART_FILE)

    fun status(): Map<String, Any?> {
        val available = try { StatFs(appContext.filesDir.path).availableBytes } catch (_: Exception) { 0L }
        val memory = memorySnapshot()
        val artifact = selectedArtifact
        val partialBytes: Long = partialFile.takeIf { it.isFile }?.length()
            ?.coerceAtMost(artifact.modelBytes) ?: 0L
        return mapOf<String, Any?>(
            "model_bytes" to artifact.modelBytes,
            "available_bytes" to available,
            "partial_bytes" to partialBytes,
            "model_present" to modelFile.isFile,
            "previous_model_present" to previousModelFile.isFile,
            "previous_partial_present" to previousPartialFile.isFile,
            "model_size_matches" to (modelFile.isFile && modelFile.length() == artifact.modelBytes),
            "download_active" to downloadActive,
            "runtime_loaded" to (engine != null),
            "inference_active" to inferenceActive,
            "runtime_busy" to runtimeOperation,
            "experimental_chat_enabled" to experimentalChatEnabled,
            "chat_available" to (experimentalChatEnabled && engine != null),
            "chat_qualified" to false,
            "available_memory_bytes" to memory.availableBytes,
            "total_memory_bytes" to memory.totalBytes,
            "low_memory" to memory.lowMemory,
            "model_id" to artifact.modelId,
            "selected_model_id" to artifact.modelId,
            "model_name" to artifact.displayName,
            "model_description" to artifact.description,
            "min_device_memory_gb" to artifact.minimumMemoryGb,
            "license" to artifact.license,
            "other_model_present" to OfflineModelArtifacts.all.any { it.modelId != artifact.modelId && File(appContext.filesDir, it.modelFile).isFile },
            "model_selection_locked" to (downloadActive || fileRemovalActive || engine != null || runtimeOperation || inferenceActive),
        )
    }

    fun setExperimentalChatEnabled(enabled: Boolean) {
        experimentalChatEnabled = enabled
        emit("status", *status().toList().toTypedArray())
    }

    fun selectModel(modelId: String) {
        val artifact = OfflineModelArtifacts.find(modelId)
        if (artifact == null) {
            emit("model_selection", "state" to "error", "message" to "That offline model option is not supported.")
            return
        }
        synchronized(this) {
            if (downloadActive || fileRemovalActive || engine != null || runtimeOperation || inferenceActive) {
                emit("model_selection", "state" to "error", "message" to "Pause or finish the current model operation and unload the model before switching.")
                return
            }
            if (selectedModelId != artifact.modelId) {
                selectedModelId = artifact.modelId
                modelPreferences.edit().putString("model_id", artifact.modelId).apply()
            }
        }
        emit("model_selection", "state" to "selected", "message" to "${artifact.displayName} selected. Its file is separate from the other option.")
        emit("status", *status().toList().toTypedArray())
    }

    fun startDownload() {
        if (disposed.get()) return
        val artifact: OfflineModelArtifact
        synchronized(this) {
            artifact = selectedArtifact
            if (downloadActive) {
                emit("download_state", "state" to "downloading", "message" to "The model download is already running.")
                return
            }
            if (fileRemovalActive || engine != null || runtimeOperation || inferenceActive) {
                emit("download_state", "state" to "error", "message" to "Unload the candidate before downloading or replacing files.")
                return
            }
            if (modelFile.exists()) {
                emit("download_state", "state" to "present", "message" to "A model file already exists. Verify it or remove it before downloading again.")
                return
            }
            downloadActive = true
            downloadCancelled.set(false)
        }
        emit("download_state", "state" to "starting", "message" to "Checking private storage before the user-requested download.")
        downloadExecutor.execute { performDownload(artifact) }
    }

    fun cancelDownload() {
        if (!downloadActive) return
        downloadCancelled.set(true)
        downloadConnection.get()?.disconnect()
    }

    private fun performDownload(artifact: OfflineModelArtifact) {
        try {
            val part = partialFile
            if (part.exists() && part.length() > artifact.modelBytes) part.delete()
            val existingBytes = part.takeIf(File::isFile)?.length() ?: 0L
            val free = StatFs(appContext.filesDir.path).availableBytes
            if (!Gemma4TransferPolicy.hasEnoughSpace(free, existingBytes, artifact.modelBytes)) {
                throw IllegalStateException("Not enough free app storage for the remaining model and a 512 MB safety reserve. Free space, then try again.")
            }
            if (existingBytes == artifact.modelBytes) {
                if (downloadCancelled.get()) throw DownloadPaused()
                if (!Gemma4FileIntegrity.verify(part, artifact.modelBytes, artifact.sha256)) {
                    part.delete()
                    throw IllegalStateException("The saved file failed SHA-256 verification and was discarded. Start a fresh download.")
                }
                if (downloadCancelled.get()) throw DownloadPaused()
                Gemma4FileIntegrity.installAtomically(part, modelFile, artifact.modelBytes, artifact.sha256)
                emit("download_state", "state" to "complete", "bytes" to artifact.modelBytes, "total" to artifact.modelBytes, "message" to "Verified model saved in app-private storage. Loading and a separate experimental-chat opt-in are still required.")
                return
            }
            if (downloadCancelled.get()) throw DownloadPaused()
            val resumeAt = Gemma4TransferPolicy.resumeOffset(existingBytes, artifact.modelBytes) ?: 0L
            emit("download_state", "state" to "downloading", "bytes" to resumeAt, "total" to artifact.modelBytes)
            val connection = openModelConnection(resumeAt, artifact)
            downloadConnection.set(connection)
            try {
                val code = connection.responseCode
                var writeAt = resumeAt
                if (resumeAt > 0 && code == HttpURLConnection.HTTP_OK) {
                    // The host ignored Range; restart cleanly rather than appending a second copy.
                    writeAt = 0L
                } else if (resumeAt > 0 && code == HttpURLConnection.HTTP_PARTIAL) {
                    val range = Gemma4TransferPolicy.parseContentRange(connection.getHeaderField("Content-Range"))
                        ?: throw IllegalStateException("The server returned an invalid resume range; the partial file was kept.")
                    if (range.start != resumeAt || range.total != artifact.modelBytes) {
                        throw IllegalStateException("The resume range did not match the pinned artifact; the partial file was kept.")
                    }
                } else if (code != HttpURLConnection.HTTP_OK) {
                    throw IllegalStateException("The model host returned HTTP $code. The partial file was kept for a later retry.")
                }
                val expectedResponseBytes = artifact.modelBytes - writeAt
                val contentLength = connection.contentLengthLong
                if (contentLength >= 0 && contentLength != expectedResponseBytes) {
                    throw IllegalStateException("The model host returned an unexpected file length. The partial file was kept.")
                }
                val lastProgressAt = longArrayOf(0L)
                connection.inputStream.buffered(1024 * 1024).use { input ->
                    FileOutputStream(part, writeAt > 0).use { output ->
                        val buffer = ByteArray(1024 * 1024)
                        var received = writeAt
                        while (true) {
                            if (downloadCancelled.get()) throw DownloadPaused()
                            val count = input.read(buffer)
                            if (count < 0) break
                            if (received + count > artifact.modelBytes) {
                                throw IllegalStateException("The downloaded data exceeded the pinned model size; the partial file was removed.")
                            }
                            output.write(buffer, 0, count)
                            received += count
                            val now = SystemClock.elapsedRealtime()
                            if (now - lastProgressAt[0] >= 500L) {
                                lastProgressAt[0] = now
                                emit("download_progress", "bytes" to received, "total" to artifact.modelBytes)
                            }
                        }
                        output.fd.sync()
                        if (received != artifact.modelBytes) {
                            throw IllegalStateException("The model download stopped before the full pinned file arrived. Resume is available.")
                        }
                    }
                }
            } finally {
                downloadConnection.compareAndSet(connection, null)
                connection.disconnect()
            }
            if (downloadCancelled.get()) throw DownloadPaused()
            emit("download_state", "state" to "verifying", "bytes" to artifact.modelBytes, "total" to artifact.modelBytes)
            if (!Gemma4FileIntegrity.verify(partialFile, artifact.modelBytes, artifact.sha256)) {
                partialFile.delete()
                throw IllegalStateException("SHA-256 verification failed. The downloaded file was discarded; start a fresh download.")
            }
            if (downloadCancelled.get()) throw DownloadPaused()
            Gemma4FileIntegrity.installAtomically(partialFile, modelFile, artifact.modelBytes, artifact.sha256)
            emit("download_state", "state" to "complete", "bytes" to artifact.modelBytes, "total" to artifact.modelBytes, "message" to "Verified model saved in app-private storage. Loading and a separate experimental-chat opt-in are still required.")
        } catch (_: DownloadPaused) {
            emit("download_state", "state" to "paused", "bytes" to (partialFile.takeIf(File::isFile)?.length() ?: 0L), "total" to artifact.modelBytes, "message" to "Download paused; verified progress stays in app-private storage. Resume is user-started.")
        } catch (error: Exception) {
            if (downloadCancelled.get()) {
                emit("download_state", "state" to "paused", "bytes" to (partialFile.takeIf(File::isFile)?.length() ?: 0L), "total" to artifact.modelBytes, "message" to "Download paused; verified progress stays in app-private storage. Resume is user-started.")
            } else {
                emit("download_state", "state" to "error", "bytes" to (partialFile.takeIf(File::isFile)?.length() ?: 0L), "total" to artifact.modelBytes, "message" to (error.message ?: "The model could not be downloaded."))
            }
        } finally {
            downloadConnection.set(null)
            downloadActive = false
            emit("status", *status().toList().toTypedArray())
        }
    }

    private fun openModelConnection(resumeAt: Long, artifact: OfflineModelArtifact): HttpURLConnection {
        var current = URL(artifact.url)
        repeat(6) {
            if (downloadCancelled.get()) throw DownloadPaused()
            if (!artifact.allowsRedirect(current.toURI())) {
                throw IllegalStateException("The model download left the approved HTTPS host allowlist.")
            }
            val connection = (current.openConnection() as HttpURLConnection).apply {
                instanceFollowRedirects = false
                connectTimeout = 20_000
                readTimeout = 60_000
                requestMethod = "GET"
                setRequestProperty("Accept-Encoding", "identity")
                setRequestProperty("User-Agent", "PersonalAgenticAI/OfflineModel")
                if (resumeAt > 0) setRequestProperty("Range", "bytes=$resumeAt-")
            }
            // Keep the in-flight connection cancellable even during DNS/TLS/header wait.
            downloadConnection.set(connection)
            val code = connection.responseCode
            if (code in 300..399) {
                val location = connection.getHeaderField("Location")
                    ?: run { connection.disconnect(); throw IllegalStateException("The model host returned an invalid redirect.") }
                val next = URL(current, location)
                if (!artifact.allowsRedirect(next.toURI())) {
                    connection.disconnect()
                    throw IllegalStateException("The model download was redirected outside the approved HTTPS hosts.")
                }
                connection.disconnect()
                current = next
            } else {
                return connection
            }
        }
        throw IllegalStateException("The model host redirected too many times.")
    }

    fun removeModel() {
        synchronized(this) {
            if (downloadActive || fileRemovalActive || engine != null || runtimeOperation || inferenceActive) {
                emit("download_state", "state" to "error", "message" to "Pause the download and unload the candidate before removing it.")
                return
            }
            fileRemovalActive = true
        }
        emit("status", *status().toList().toTypedArray())
        downloadExecutor.execute {
            try {
                val deletedModel = !modelFile.exists() || modelFile.delete()
                val deletedPart = !partialFile.exists() || partialFile.delete()
                val deletedPreviousModel = !previousModelFile.exists() || previousModelFile.delete()
                val deletedPreviousPart = !previousPartialFile.exists() || previousPartialFile.delete()
                if (!deletedModel || !deletedPart || !deletedPreviousModel || !deletedPreviousPart) throw IllegalStateException("The app could not remove all selected model files.")
                emit("download_state", "state" to "removed", "bytes" to 0L, "total" to selectedArtifact.modelBytes, "message" to "The selected model files and any previous Gemma 4 files were removed from app-private storage. The other model option was kept.")
            } catch (error: Exception) {
                emit("download_state", "state" to "error", "message" to (error.message ?: "The model files could not be removed."))
            } finally {
                fileRemovalActive = false
                emit("status", *status().toList().toTypedArray())
            }
        }
    }

    fun loadForScreening() {
        if (disposed.get()) return
        inferenceScope.launch {
            runtimeMutex.withLock {
                val artifact = selectedArtifact
                if (engine != null) {
                    emit("runtime_state", "state" to "loaded", "message" to if (experimentalChatEnabled) "The selected model is loaded for fixed screening and explicitly opted-in experimental chat; it is not qualified." else "The selected model is loaded for screening. Turn on experimental chat in Settings if you want to use it for normal chat.")
                    return@withLock
                }
                if (runtimeOperation || inferenceActive) {
                    emit("runtime_state", "state" to "error", "message" to "A model operation is already running.")
                    return@withLock
                }
                runtimeOperation = true
                val memory = memorySnapshot()
                emit("runtime_state", "state" to "preflight", "available_memory_bytes" to memory.availableBytes, "low_memory" to memory.lowMemory, "message" to "Checking Android's memory warning before loading. The reading is not a guarantee of fit.")
                try {
                    if (memory.lowMemory) {
                        throw IllegalStateException("Android currently reports low memory. Close other apps and try later; loading is not guaranteed even when this warning clears. No network fallback was used.")
                    }
                    if (!Gemma4FileIntegrity.verify(modelFile, artifact.modelBytes, artifact.sha256)) {
                        throw IllegalStateException("The installed model failed its size or SHA-256 check. Remove it and download again.")
                    }
                    emit("runtime_state", "state" to "loading", "message" to "Loading ${artifact.displayName} with the LiteRT-LM CPU backend. This model remains unqualified and may use substantial RAM.")
                    val candidate = Engine(
                        EngineConfig(
                            modelPath = modelFile.absolutePath,
                            backend = Backend.CPU(),
                            cacheDir = appContext.cacheDir.absolutePath,
                        ),
                    )
                    try {
                        candidate.initialize()
                    } catch (error: Exception) {
                        // LiteRT-LM requires that an Engine whose initialization failed is not closed.
                        throw IllegalStateException("The model could not initialize on this device. It remains unqualified; no online fallback was used.", error)
                    }
                    engine = candidate
                    emit("runtime_state", "state" to "loaded", "message" to if (experimentalChatEnabled) "The selected model is loaded for fixed screening and explicitly opted-in experimental chat. Quality and Redmi/HyperOS behavior are unqualified." else "The selected model is loaded for screening; normal chat needs separate opt-in in Settings. The model is not qualified.")
                } catch (error: OutOfMemoryError) {
                    emit("runtime_state", "state" to "error", "message" to "Android ran out of memory while loading the selected model. It remains unqualified; close other apps and retry only if you choose. No online fallback was used.")
                } catch (error: Exception) {
                    emit("runtime_state", "state" to "error", "message" to (error.message ?: "The model could not be loaded locally."))
                } finally {
                    runtimeOperation = false
                    emit("status", *status().toList().toTypedArray())
                }
            }
        }
    }

    fun runQualification(fixtureId: String) {
        val prompt = Gemma4QualificationPrompts.find(fixtureId)
        if (prompt == null) {
            emit("inference_state", "state" to "error", "message" to "Unknown fixed screening prompt.")
            return
        }
        inferenceScope.launch {
            runtimeMutex.withLock {
                val activeEngine = engine
                if (activeEngine == null) {
                    emit("inference_state", "state" to "error", "message" to "Load the downloaded candidate for screening first.")
                    return@withLock
                }
                if (inferenceActive || runtimeOperation) {
                    emit("inference_state", "state" to "error", "message" to "Another local model operation is already running.")
                    return@withLock
                }
                if (memorySnapshot().lowMemory) {
                    emit("inference_state", "state" to "error", "message" to "Android reports low memory, so screening did not start. The candidate remains unqualified.")
                    return@withLock
                }
                inferenceActive = true
                activePurpose = "screening"
                inferenceCancelRequested = false
                val memoryBefore = currentPssMb()
                val thermalBefore = currentThermalStatus()
                val startedAt = SystemClock.elapsedRealtime()
                val output = StringBuilder()
                var conversation: Conversation? = null
                emit("inference_state", "state" to "running", "fixture_id" to prompt.id, "label" to prompt.label, "message" to "Running a fixed test prompt locally; nothing is sent to a service.")
                try {
                    conversation = activeEngine.createConversation(
                        ConversationConfig(maxOutputToken = 256, automaticToolCalling = false),
                    )
                    activeConversation = conversation
                    if (inferenceCancelRequested) throw CancellationException()
                    conversation.sendMessageAsync(prompt.text).collect { chunk ->
                        val text = chunk.toString()
                        output.append(text)
                        emit("inference_delta", "fixture_id" to prompt.id, "text" to text)
                    }
                    emit(
                        "inference_result",
                        "state" to "complete",
                        "fixture_id" to prompt.id,
                        "label" to prompt.label,
                        "text" to output.toString(),
                        "elapsed_ms" to (SystemClock.elapsedRealtime() - startedAt),
                        "pss_before_mb" to memoryBefore,
                        "pss_after_mb" to currentPssMb(),
                        "thermal_before" to thermalBefore,
                        "thermal_after" to currentThermalStatus(),
                        "message" to "Screening result only. Review correctness, language, units and concision; this is not an activation or pass result.",
                    )
                } catch (_: CancellationException) {
                    emit("inference_state", "state" to "cancelled", "fixture_id" to prompt.id, "text" to output.toString(), "message" to "Local inference was cancelled. This candidate remains unqualified.")
                } catch (error: OutOfMemoryError) {
                    emit("inference_state", "state" to "error", "fixture_id" to prompt.id, "text" to output.toString(), "message" to "Android ran out of memory during local screening. The candidate remains unqualified; no network fallback was used.")
                } catch (error: Exception) {
                    emit("inference_state", "state" to "error", "fixture_id" to prompt.id, "text" to output.toString(), "message" to (error.message ?: "Local inference failed; no network fallback was used."))
                } finally {
                    activeConversation = null
                    try { conversation?.close() } catch (_: Exception) {}
                    inferenceActive = false
                    activePurpose = null
                    emit("status", *status().toList().toTypedArray())
                }
            }
        }
    }

    /** Run an arbitrary user chat prompt only after explicit opt-in and explicit model loading. */
    fun runChat(
        prompt: String,
        optedIn: Boolean,
        complete: (String?, String?, String?) -> Unit,
    ) {
        val delivered = AtomicBoolean(false)
        val finish: (String?, String?, String?) -> Unit = { text, code, message ->
            if (delivered.compareAndSet(false, true)) {
                mainHandler.post { complete(text, code, message) }
            }
        }
        if (disposed.get()) {
            finish(null, "unavailable", "The local model runtime is closing. No online fallback was used.")
            return
        }
        if (!optedIn || !experimentalChatEnabled) {
            finish(null, "opt_in_required", "Turn on experimental local chat in Settings first. No online fallback was used.")
            return
        }
        if (prompt.isBlank() || prompt.toByteArray(Charsets.UTF_8).size > 48 * 1024) {
            finish(null, "invalid_prompt", "The local prompt is empty or too large. Shorten it and try again; no online fallback was used.")
            return
        }
        val requestCancelled = AtomicBoolean(false)
        activeChatCancellation = requestCancelled
        inferenceScope.launch {
            try {
                runtimeMutex.withLock {
                    if (requestCancelled.get()) {
                        finish(null, "cancelled", "Local generation was cancelled before it started. Nothing was sent online.")
                        return@withLock
                    }
                    val activeEngine = engine
                    if (activeEngine == null) {
                        finish(null, "model_unavailable", "Download and load a model from Settings > Offline Model & Experimental Chat first. No online fallback was used.")
                        return@withLock
                    }
                    if (inferenceActive || runtimeOperation) {
                        finish(null, "busy", "The local model is busy with another operation. Wait for it to finish and retry explicitly.")
                        return@withLock
                    }
                    val memory = memorySnapshot()
                    if (memory.lowMemory) {
                        finish(null, "memory_preflight", "Android reports low memory, so local chat did not start. Close other apps and retry when the warning clears; no online fallback was used.")
                        return@withLock
                    }
                    if (requestCancelled.get()) {
                        finish(null, "cancelled", "Local generation was cancelled before it started. Nothing was sent online.")
                        return@withLock
                    }
                    inferenceCancelRequested = false
                    inferenceActive = true
                    activePurpose = "chat"
                    emit("inference_state", "state" to "running", "purpose" to "chat", "message" to "Generating locally with the selected experimental model. No prompt is sent to a service.")
                    var conversation: Conversation? = null
                    val output = StringBuilder()
                    var finalState = "error"
                    try {
                        if (requestCancelled.get() || inferenceCancelRequested) throw CancellationException()
                        conversation = activeEngine.createConversation(
                            ConversationConfig(maxOutputToken = 512, automaticToolCalling = false),
                        )
                        activeConversation = conversation
                        if (requestCancelled.get() || inferenceCancelRequested) throw CancellationException()
                        conversation.sendMessageAsync(prompt).collect { chunk -> output.append(chunk.toString()) }
                        val answer = output.toString()
                        if (answer.isBlank()) {
                            finish(null, "empty_response", "The local model returned no text. No online fallback was used.")
                        } else {
                            finalState = "complete"
                            finish(answer, null, null)
                        }
                    } catch (_: CancellationException) {
                        finalState = "cancelled"
                        finish(null, "cancelled", "Local generation was cancelled. Nothing was sent online.")
                    } catch (error: OutOfMemoryError) {
                        finish(null, "memory_exhausted", "Android ran out of memory during local generation. The model is still unqualified; no online fallback was used.")
                    } catch (error: Exception) {
                        finish(null, "inference_failed", error.message ?: "Local generation failed. No online fallback was used.")
                    } finally {
                        activeConversation = null
                        try { conversation?.close() } catch (_: Exception) {}
                        inferenceActive = false
                        activePurpose = null
                        inferenceCancelRequested = false
                        emit("inference_state", "state" to finalState, "purpose" to "chat")
                        emit("status", *status().toList().toTypedArray())
                    }
                }
            } catch (_: CancellationException) {
                finish(null, "cancelled", "Local generation was cancelled. Nothing was sent online.")
            } catch (error: Exception) {
                finish(null, "inference_failed", error.message ?: "Local generation failed. No online fallback was used.")
            } finally {
                if (activeChatCancellation === requestCancelled) activeChatCancellation = null
            }
        }
    }

    fun cancelChat() {
        activeChatCancellation?.set(true)
        if (activePurpose == "chat") cancelInference()
    }

    fun cancelInference() {
        if (!inferenceActive) return
        inferenceCancelRequested = true
        // Capture the current conversation so a delayed cancellation cannot hit a later turn.
        val conversation = activeConversation ?: return
        controlScope.launch {
            try {
                conversation.cancelProcess()
            } catch (_: Exception) {
                // The stream's completion handler owns cleanup and reports the final state.
            }
        }
    }

    fun unloadCandidate() {
        cancelInference()
        inferenceScope.launch {
            runtimeMutex.withLock {
                if (inferenceActive) {
                    emit("runtime_state", "state" to "busy", "message" to "Stopping local inference before releasing model memory.")
                    while (inferenceActive) kotlinx.coroutines.delay(50)
                }
                closeEngineOnce()
                emit("runtime_state", "state" to "unloaded", "message" to "Candidate unloaded; its verified file remains in app-private storage.")
                emit("status", *status().toList().toTypedArray())
            }
        }
    }

    fun onAppPaused() {
        cancelDownload()
        cancelChat()
        cancelInference()
        unloadCandidate()
    }

    fun shutdown() {
        if (!disposed.compareAndSet(false, true)) return
        cancelDownload()
        cancelChat()
        cancelInference()
        val cleanup = inferenceScope.launch {
            runtimeMutex.withLock { closeEngineOnce() }
        }
        cleanup.invokeOnCompletion {
            controlScope.cancel()
            inferenceScope.cancel()
            inferenceDispatcher.close()
            inferenceExecutor.shutdown()
            downloadExecutor.shutdown()
        }
    }

    private fun closeEngineOnce() {
        val oldConversation = activeConversation
        activeConversation = null
        try { oldConversation?.close() } catch (_: Exception) {}
        val oldEngine = engine
        engine = null
        try { oldEngine?.close() } catch (_: Exception) {}
    }

    private data class MemorySnapshot(val availableBytes: Long, val totalBytes: Long, val lowMemory: Boolean)

    private fun memorySnapshot(): MemorySnapshot = try {
        val manager = appContext.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val info = ActivityManager.MemoryInfo()
        manager.getMemoryInfo(info)
        MemorySnapshot(info.availMem, info.totalMem, info.lowMemory)
    } catch (_: Exception) {
        MemorySnapshot(-1L, -1L, true)
    }

    private fun currentPssMb(): Long = try {
        val info = Debug.MemoryInfo()
        Debug.getMemoryInfo(info)
        info.totalPss.toLong() / 1024L
    } catch (_: Exception) { -1L }

    @Suppress("NewApi")
    private fun currentThermalStatus(): Int = try {
        if (android.os.Build.VERSION.SDK_INT >= 29) {
            (appContext.getSystemService(Context.POWER_SERVICE) as PowerManager).currentThermalStatus
        } else -1
    } catch (_: Exception) { -1 }

    private fun emit(kind: String, vararg values: Pair<String, Any?>) {
        val event = linkedMapOf<String, Any?>("kind" to kind)
        values.forEach { (key, value) -> event[key] = value }
        mainHandler.post { publish(event) }
    }

    private class DownloadPaused : Exception()
}
