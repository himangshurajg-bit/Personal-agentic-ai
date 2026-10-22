package dev.personalagent.personal_assistant

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

internal object Gemma4Artifact {
    const val MODEL_ID = "gemma-4-E4B-it"
    const val MODEL_FILE = "gemma-4-E4B-it.litertlm"
    const val PART_FILE = "$MODEL_FILE.part"
    const val MODEL_BYTES = 3_659_530_240L
    const val SHA256 = "0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0"
    const val REVISION = "e6a3892a8c22cf87ff99583996149cf3cb32452b"
    const val URL = "https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/$REVISION/$MODEL_FILE"
    const val LITERT_LM_VERSION = "0.18.1"
    const val LICENSE = "Apache-2.0"
    const val SAFETY_RESERVE_BYTES = 512L * 1024L * 1024L

    fun allowsRedirect(uri: URI): Boolean {
        if (!uri.scheme.equals("https", ignoreCase = true) || uri.userInfo != null) return false
        val host = uri.host?.lowercase(Locale.ROOT) ?: return false
        return host == "huggingface.co" || host.endsWith(".huggingface.co") || host.endsWith(".hf.co")
    }
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
        val remaining = (expectedBytes - partialBytes.coerceIn(0, expectedBytes)).coerceAtLeast(0)
        return availableBytes >= remaining + Gemma4Artifact.SAFETY_RESERVE_BYTES
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

    private val inferenceExecutor = Executors.newSingleThreadExecutor()
    private val inferenceDispatcher = inferenceExecutor.asCoroutineDispatcher()
    private val inferenceScope = CoroutineScope(SupervisorJob() + inferenceDispatcher)
    private val runtimeMutex = Mutex()
    @Volatile private var engine: Engine? = null
    @Volatile private var activeConversation: Conversation? = null
    @Volatile private var inferenceActive = false
    @Volatile private var runtimeOperation = false
    private val disposed = AtomicBoolean(false)

    private val modelFile get() = File(appContext.filesDir, Gemma4Artifact.MODEL_FILE)
    private val partialFile get() = File(appContext.filesDir, Gemma4Artifact.PART_FILE)

    fun status(): Map<String, Any?> {
        val available = try { StatFs(appContext.filesDir.path).availableBytes } catch (_: Exception) { 0L }
        val partialBytes: Long = partialFile.takeIf { it.isFile }?.length()
            ?.coerceAtMost(Gemma4Artifact.MODEL_BYTES) ?: 0L
        return mapOf<String, Any?>(
            "model_bytes" to Gemma4Artifact.MODEL_BYTES,
            "available_bytes" to available,
            "partial_bytes" to partialBytes,
            "model_present" to modelFile.isFile,
            "model_size_matches" to (modelFile.isFile && modelFile.length() == Gemma4Artifact.MODEL_BYTES),
            "download_active" to downloadActive,
            "runtime_loaded" to (engine != null),
            "inference_active" to inferenceActive,
            "runtime_busy" to runtimeOperation,
            "chat_available" to false,
            "model_id" to Gemma4Artifact.MODEL_ID,
            "license" to Gemma4Artifact.LICENSE,
        )
    }

    fun startDownload() {
        if (disposed.get()) return
        synchronized(this) {
            if (downloadActive) {
                emit("download_state", "state" to "downloading", "message" to "The model download is already running.")
                return
            }
            if (engine != null || runtimeOperation || inferenceActive) {
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
        downloadExecutor.execute { performDownload() }
    }

    fun cancelDownload() {
        if (!downloadActive) return
        downloadCancelled.set(true)
        downloadConnection.get()?.disconnect()
    }

    private fun performDownload() {
        try {
            val part = partialFile
            if (part.exists() && part.length() > Gemma4Artifact.MODEL_BYTES) part.delete()
            val existingBytes = part.takeIf(File::isFile)?.length() ?: 0L
            val free = StatFs(appContext.filesDir.path).availableBytes
            if (!Gemma4TransferPolicy.hasEnoughSpace(free, existingBytes, Gemma4Artifact.MODEL_BYTES)) {
                throw IllegalStateException("Not enough free app storage for the remaining model and a 512 MB safety reserve. Free space, then try again.")
            }
            if (downloadCancelled.get()) throw DownloadPaused()
            val resumeAt = Gemma4TransferPolicy.resumeOffset(existingBytes, Gemma4Artifact.MODEL_BYTES) ?: 0L
            emit("download_state", "state" to "downloading", "bytes" to resumeAt, "total" to Gemma4Artifact.MODEL_BYTES)
            val connection = openModelConnection(resumeAt)
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
                    if (range.start != resumeAt || range.total != Gemma4Artifact.MODEL_BYTES) {
                        throw IllegalStateException("The resume range did not match the pinned artifact; the partial file was kept.")
                    }
                } else if (code != HttpURLConnection.HTTP_OK) {
                    throw IllegalStateException("The model host returned HTTP $code. The partial file was kept for a later retry.")
                }
                val expectedResponseBytes = Gemma4Artifact.MODEL_BYTES - writeAt
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
                            if (received + count > Gemma4Artifact.MODEL_BYTES) {
                                throw IllegalStateException("The downloaded data exceeded the pinned model size; the partial file was removed.")
                            }
                            output.write(buffer, 0, count)
                            received += count
                            val now = SystemClock.elapsedRealtime()
                            if (now - lastProgressAt[0] >= 500L) {
                                lastProgressAt[0] = now
                                emit("download_progress", "bytes" to received, "total" to Gemma4Artifact.MODEL_BYTES)
                            }
                        }
                        output.fd.sync()
                        if (received != Gemma4Artifact.MODEL_BYTES) {
                            throw IllegalStateException("The model download stopped before the full pinned file arrived. Resume is available.")
                        }
                    }
                }
            } finally {
                downloadConnection.compareAndSet(connection, null)
                connection.disconnect()
            }
            if (downloadCancelled.get()) throw DownloadPaused()
            emit("download_state", "state" to "verifying", "bytes" to Gemma4Artifact.MODEL_BYTES, "total" to Gemma4Artifact.MODEL_BYTES)
            if (!Gemma4FileIntegrity.verify(partialFile, Gemma4Artifact.MODEL_BYTES, Gemma4Artifact.SHA256)) {
                partialFile.delete()
                throw IllegalStateException("SHA-256 verification failed. The downloaded file was discarded; start a fresh download.")
            }
            Gemma4FileIntegrity.installAtomically(partialFile, modelFile, Gemma4Artifact.MODEL_BYTES, Gemma4Artifact.SHA256)
            emit("download_state", "state" to "complete", "bytes" to Gemma4Artifact.MODEL_BYTES, "total" to Gemma4Artifact.MODEL_BYTES, "message" to "Verified model saved in app-private storage. It is not enabled for chat.")
        } catch (_: DownloadPaused) {
            emit("download_state", "state" to "paused", "bytes" to (partialFile.takeIf(File::isFile)?.length() ?: 0L), "total" to Gemma4Artifact.MODEL_BYTES, "message" to "Download paused; verified progress stays in app-private storage. Resume is user-started.")
        } catch (error: Exception) {
            if (downloadCancelled.get()) {
                emit("download_state", "state" to "paused", "bytes" to (partialFile.takeIf(File::isFile)?.length() ?: 0L), "total" to Gemma4Artifact.MODEL_BYTES, "message" to "Download paused; verified progress stays in app-private storage. Resume is user-started.")
            } else {
                emit("download_state", "state" to "error", "bytes" to (partialFile.takeIf(File::isFile)?.length() ?: 0L), "total" to Gemma4Artifact.MODEL_BYTES, "message" to (error.message ?: "The model could not be downloaded."))
            }
        } finally {
            downloadConnection.set(null)
            downloadActive = false
            emit("status", *status().toList().toTypedArray())
        }
    }

    private fun openModelConnection(resumeAt: Long): HttpURLConnection {
        var current = URL(Gemma4Artifact.URL)
        repeat(6) {
            if (downloadCancelled.get()) throw DownloadPaused()
            if (!Gemma4Artifact.allowsRedirect(current.toURI())) {
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
                if (!Gemma4Artifact.allowsRedirect(next.toURI())) {
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
        if (downloadActive || engine != null || runtimeOperation || inferenceActive) {
            emit("download_state", "state" to "error", "message" to "Pause the download and unload the candidate before removing it.")
            return
        }
        downloadExecutor.execute {
            try {
                val deletedModel = !modelFile.exists() || modelFile.delete()
                val deletedPart = !partialFile.exists() || partialFile.delete()
                if (!deletedModel || !deletedPart) throw IllegalStateException("The app could not remove its model files.")
                emit("download_state", "state" to "removed", "bytes" to 0L, "total" to Gemma4Artifact.MODEL_BYTES, "message" to "The model and any partial download were removed from app-private storage.")
            } catch (error: Exception) {
                emit("download_state", "state" to "error", "message" to (error.message ?: "The model files could not be removed."))
            }
            emit("status", *status().toList().toTypedArray())
        }
    }

    fun loadForScreening() {
        if (disposed.get()) return
        inferenceScope.launch {
            runtimeMutex.withLock {
                if (engine != null) {
                    emit("runtime_state", "state" to "loaded", "message" to "Candidate is loaded for screening only; normal chat remains unavailable.")
                    return@withLock
                }
                if (runtimeOperation || inferenceActive) {
                    emit("runtime_state", "state" to "error", "message" to "A model operation is already running.")
                    return@withLock
                }
                runtimeOperation = true
                emit("runtime_state", "state" to "verifying", "message" to "Rechecking the pinned model size and SHA-256 before local loading.")
                try {
                    if (!Gemma4FileIntegrity.verify(modelFile, Gemma4Artifact.MODEL_BYTES, Gemma4Artifact.SHA256)) {
                        throw IllegalStateException("The installed model failed its size or SHA-256 check. Remove it and download again.")
                    }
                    emit("runtime_state", "state" to "loading", "message" to "Loading Gemma 4 E4B with the LiteRT-LM CPU backend. This can take a while and may use several GB of RAM.")
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
                    emit("runtime_state", "state" to "loaded", "message" to "Candidate loaded for local screening only. It is not available in normal chat.")
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
                inferenceActive = true
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
                } catch (error: Exception) {
                    emit("inference_state", "state" to "error", "fixture_id" to prompt.id, "text" to output.toString(), "message" to (error.message ?: "Local inference failed; no network fallback was used."))
                } finally {
                    activeConversation = null
                    try { conversation?.close() } catch (_: Exception) {}
                    inferenceActive = false
                    emit("status", *status().toList().toTypedArray())
                }
            }
        }
    }

    fun cancelInference() {
        if (!inferenceActive) return
        inferenceScope.launch {
            try {
                activeConversation?.cancelProcess()
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
        cancelInference()
        unloadCandidate()
    }

    fun shutdown() {
        if (!disposed.compareAndSet(false, true)) return
        cancelDownload()
        cancelInference()
        val cleanup = inferenceScope.launch {
            runtimeMutex.withLock { closeEngineOnce() }
        }
        cleanup.invokeOnCompletion {
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
