package com.myra.ultra.nativeapp

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.io.IOException
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import okhttp3.Call
import okhttp3.Callback
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import org.json.JSONObject

/** One user-started, foreground-only Gemini Live audio session. */
internal class GeminiLiveSession(
    private val apiKey: String,
    private val systemInstruction: String,
    private val onStatus: (String) -> Unit,
    private val onTranscript: (user: Boolean, text: String) -> Unit,
    private val readBatteryStatus: () -> String,
    private val reviewAndShareLocation: suspend () -> String,
    private val reviewAndSetVolume: suspend (GeminiVolumeRequest) -> String,
    private val reviewAndSetBrightness: suspend (GeminiBrightnessRequest) -> String,
    private val reviewAndSetTimer: suspend (ClockTimerRequest) -> String,
    private val reviewAndSetAlarm: suspend (ClockAlarmRequest) -> String,
    private val reviewAndNavigate: suspend (GeminiNavigateRequest) -> String,
    private val reviewAndDownload: suspend (GeminiDownloadRequest) -> String,
    private val reviewAndSetTorch: suspend (GeminiTorchRequest) -> String,
    private val reviewAndShowToast: suspend (GeminiToastRequest) -> String,
    private val onError: (String) -> Unit,
    initialBargeInEnabled: Boolean = false,
) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val audioExecutor = Executors.newSingleThreadExecutor()
    private val playerExecutor = Executors.newSingleThreadExecutor()
    private val playbackLock = Any()
    private val playbackTimeline = SourceVoicePlaybackTimeline()
    private var playbackGeneration = 0L
    private var playbackIdleRunnable: Runnable? = null
    private val tokenClient = OkHttpClient.Builder().callTimeout(20, TimeUnit.SECONDS).build()
    private val client = OkHttpClient.Builder().readTimeout(0, TimeUnit.MILLISECONDS).build()
    @Volatile private var tokenCall: Call? = null
    @Volatile private var socket: WebSocket? = null
    @Volatile private var recorder: AudioRecord? = null
    @Volatile private var recording = false
    @Volatile private var closed = false
    @Volatile private var player: AudioTrack? = null
    private val userText = StringBuilder()
    private val modelText = StringBuilder()
    private val micGate = GeminiLiveMicGate().apply { setBargeInEnabled(initialBargeInEnabled) }
    private val toolScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val resumption = GeminiLiveResumptionState()
    private val reconnectLock = Any()
    @Volatile private var reconnectScheduled = false
    private var reconnectAttempts = 0
    private var reconnectRunnable: Runnable? = null
    private var toolAttemptedThisTurn = false

    /** Allow the owner to change interruption behavior while a session is active. */
    fun setBargeInEnabled(enabled: Boolean) {
        micGate.setBargeInEnabled(enabled)
    }

    fun start() {
        requestTokenAndConnect()
    }

    private fun requestTokenAndConnect() {
        if (closed) return
        postStatus(if (reconnectScheduled) "Reconnecting to Gemini Live…" else "Requesting a short-lived Gemini Live token…")
        val tokenRequest = try {
            GeminiLiveAuth.createTokenRequest(apiKey, systemInstruction)
        } catch (error: Exception) {
            fail(error.message?.take(240) ?: "Could not prepare Gemini Live authentication.")
            return
        }
        val call = tokenClient.newCall(tokenRequest.request)
        tokenCall = call
        call.enqueue(object : Callback {
            override fun onFailure(call: Call, error: IOException) {
                if (!closed && !call.isCanceled()) {
                    fail(if (reconnectScheduled) "Could not reconnect to Gemini Live. Start live voice again." else "Could not request a short-lived Gemini Live token. Check connection, API key access and quota.")
                }
            }

            override fun onResponse(call: Call, response: Response) {
                try {
                    val token = response.use {
                        val body = it.body ?: throw IOException("Gemini returned an empty Live token response.")
                        val bytes = body.source().readByteArray(GeminiLiveAuth.MAX_RESPONSE_BYTES + 1)
                        if (bytes.size.toLong() > GeminiLiveAuth.MAX_RESPONSE_BYTES) throw IOException("Gemini Live token response was oversized.")
                        GeminiLiveAuth.parseTokenResponse(it.code, String(bytes, Charsets.UTF_8), tokenRequest)
                    }
                    if (!closed) connect(token)
                } catch (error: Exception) {
                    if (!closed) fail(error.message?.take(240) ?: "Could not create a Gemini Live session.")
                } finally {
                    if (tokenCall === call) tokenCall = null
                    tokenClient.connectionPool.evictAll()
                }
            }
        })
    }

    private fun connect(token: GeminiLiveAuth.EphemeralToken) {
        val url = try { GeminiLiveAuth.liveWebSocketUrl(token) }
        catch (error: Exception) {
            fail(error.message?.take(240) ?: "Gemini Live token expired before connecting. Start again.")
            return
        }
        postStatus(if (reconnectScheduled) "Resuming Gemini Live…" else "Connecting to Gemini Live…")
        val request = Request.Builder().url(url).build()
        val newSocket = client.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                if (closed || socket !== webSocket) { webSocket.close(1000, "Session no longer active"); return }
                val handle = resumption.handleForSetup(SystemClock.elapsedRealtime())
                if (reconnectScheduled && handle == null) {
                    fail("Gemini Live session context expired before it could resume. Start live voice again.")
                    return
                }
                val sent = try { webSocket.send(GeminiLiveProtocol.setupMessage(systemInstruction, handle)) }
                catch (error: Exception) { fail(error.message?.take(240) ?: "Could not configure Gemini Live resumption."); false }
                if (!sent) fail("Could not configure the Gemini Live session.")
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                if (closed || socket !== webSocket) return
                try {
                    handleMessage(webSocket, GeminiLiveProtocol.parseServerMessage(text))
                } catch (error: Exception) {
                    fail(error.message?.take(240) ?: "Gemini Live returned an invalid response.")
                }
            }

            override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                if (closed || socket !== webSocket) return
                try {
                    handleMessage(webSocket, GeminiLiveProtocol.parseServerMessage(bytes.utf8()))
                } catch (error: Exception) {
                    fail(error.message?.take(240) ?: "Gemini Live returned an invalid response.")
                }
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                if (closed || socket !== webSocket) return
                val code = response?.code
                if (code == 401 || code == 403) {
                    fail("Gemini rejected the short-lived Live token (HTTP $code). Start live voice again; check Live API access if it repeats.")
                } else {
                    scheduleReconnect(webSocket, null)
                }
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                if (closed) { stopAudio(); return }
                if (socket !== webSocket) return
                scheduleReconnect(webSocket, null)
            }
        })
        synchronized(reconnectLock) {
            if (closed) newSocket.close(1000, "Session no longer active") else socket = newSocket
        }
    }

    private fun scheduleReconnect(webSocket: WebSocket, goAwayTimeLeftMillis: Long?) {
        val now = SystemClock.elapsedRealtime()
        var shouldFail = false
        var task: Runnable? = null
        var delayMillis = 0L
        synchronized(reconnectLock) {
            // socket identity makes callback races idempotent; a reconnecting socket may itself fail
            // before setup completes, in which case it must consume the next bounded attempt.
            if (closed || socket !== webSocket) return
            val handle = resumption.handleForSetup(now)
            if (handle == null || reconnectAttempts >= GeminiLiveResumptionState.MAX_RECONNECT_ATTEMPTS) {
                socket = null
                shouldFail = true
            } else {
                reconnectScheduled = true
                reconnectAttempts += 1
                resumption.markSessionEnded(now)
                socket = null // Ignore late callbacks from the session being replaced.
                delayMillis = goAwayTimeLeftMillis?.let(GeminiLiveResumptionState::goAwayDelayMillis)
                    ?: GeminiLiveResumptionState.retryDelayMillis(reconnectAttempts)
                task = Runnable {
                    synchronized(reconnectLock) {
                        reconnectRunnable = null
                        if (closed || !reconnectScheduled) return@Runnable
                    }
                    requestTokenAndConnect()
                }
                reconnectRunnable = task
            }
        }
        if (shouldFail) {
            fail("Gemini Live disconnected and the session could not be resumed. Start live voice again.")
            return
        }
        stopAudio()
        webSocket.close(1000, "Reconnecting Gemini Live")
        task?.let { mainHandler.postDelayed(it, delayMillis) }
    }

    private fun handleMessage(webSocket: WebSocket, events: List<GeminiLiveEvent>) {
        for (event in events) {
            if (closed || socket !== webSocket) return
            when (event) {
            GeminiLiveEvent.SetupComplete -> {
                synchronized(reconnectLock) {
                    if (closed || socket !== webSocket) return
                    resumption.markSessionActive()
                    reconnectScheduled = false
                }
                postStatus("Listening · tap Stop to end")
                startAudio()
            }
            is GeminiLiveEvent.SessionResumptionUpdate -> synchronized(reconnectLock) {
                if (!closed && socket === webSocket) resumption.update(event.resumable, event.newHandle)
            }
            is GeminiLiveEvent.GoAway -> scheduleReconnect(webSocket, event.timeLeftMillis)
            is GeminiLiveEvent.InputTranscript -> synchronized(userText) { appendBounded(userText, event.text) }
            is GeminiLiveEvent.ToolCall -> {
                postStatus("Thinking")
                val utterance = synchronized(userText) { userText.toString().trim() }
                if (toolAttemptedThisTurn) {
                    sendToolResponse(event.call, "Only one device tool is allowed per spoken turn; no additional action was taken.")
                } else {
                    toolAttemptedThisTurn = true
                    when (event.call.name) {
                        GeminiLiveProtocol.SHOW_TOAST_TOOL -> {
                            val request = try { GeminiToastPolicy.request(event.call.args) } catch (_: Exception) { null }
                            if (request == null || !GeminiToastPolicy.hasExplicitIntent(utterance, request)) {
                                sendToolResponse(event.call, "The current spoken request did not directly ask to show a toast with this exact text; nothing was displayed.")
                            } else toolScope.launch {
                                val outcome = try { reviewAndShowToast(request).take(1000) }
                                catch (_: Exception) { "The toast was not displayed; no success is assumed." }
                                sendToolResponse(event.call, outcome)
                            }
                        }
                        GeminiLiveProtocol.SHARE_LOCATION_TOOL -> {
                            if (!GeminiLocationSharePolicy.hasExplicitIntent(utterance)) {
                                sendToolResponse(event.call, "The current spoken request did not directly ask for the user's current location; no location permission or data was used.")
                            } else toolScope.launch {
                                val outcome = try { reviewAndShareLocation().take(1000) }
                                catch (_: Exception) { "The location could not be shared; no success is assumed." }
                                sendToolResponse(event.call, outcome)
                            }
                        }
                        GeminiLiveProtocol.BATTERY_STATUS_TOOL -> {
                            val result = if (!GeminiLiveBatteryPolicy.hasExplicitIntent(utterance)) {
                                "The current spoken request did not directly ask about battery status; no device data was read."
                            } else try {
                                readBatteryStatus().take(1000)
                            } catch (_: Exception) {
                                "Battery status is unavailable; Android did not provide a reading."
                            }
                            sendToolResponse(event.call, result)
                        }
                        GeminiLiveProtocol.SET_VOLUME_TOOL -> {
                            val request = GeminiSafeTools.volumeRequest(event.call.args)
                            val result = if (!GeminiLiveActionPolicy.hasExplicitVolumeIntent(utterance, request)) {
                                "The current spoken request did not directly ask for this exact stream and percentage; volume was not changed."
                            } else null
                            if (result != null) sendToolResponse(event.call, result)
                            else toolScope.launch {
                                val outcome = try { reviewAndSetVolume(request).take(1000) }
                                catch (_: Exception) { "The volume change could not be completed; no success is assumed." }
                                sendToolResponse(event.call, outcome)
                            }
                        }
                        GeminiLiveProtocol.SET_BRIGHTNESS_TOOL -> {
                            val request = GeminiSafeTools.brightnessRequest(event.call.args)
                            if (!GeminiLiveActionPolicy.hasExplicitBrightnessIntent(utterance, request)) {
                                sendToolResponse(event.call, "The current spoken request did not directly ask for this exact MYRA window brightness level; no brightness change was made.")
                            } else toolScope.launch {
                                val outcome = try { reviewAndSetBrightness(request).take(1000) }
                                catch (_: Exception) { "The MYRA window brightness change could not be completed; no success is assumed." }
                                sendToolResponse(event.call, outcome)
                            }
                        }
                        GeminiLiveProtocol.SET_TIMER_TOOL -> {
                            val request = GeminiTimerPolicy.request(event.call.args)
                            val result = if (request == null || !GeminiTimerPolicy.hasExplicitIntent(utterance, request)) {
                                "The current spoken request did not directly ask for this exact timer duration; no Clock handoff was started."
                            } else null
                            if (result != null) sendToolResponse(event.call, result)
                            else toolScope.launch {
                                val outcome = try { reviewAndSetTimer(request!!).take(1000) }
                                catch (_: Exception) { "The timer handoff could not be completed; no success is assumed." }
                                sendToolResponse(event.call, outcome)
                            }
                        }
                        GeminiLiveProtocol.DOWNLOAD_FILE_TOOL -> {
                            val request = try { GeminiDownloadPolicy.request(event.call.args) } catch (_: Exception) { null }
                            if (request == null || !GeminiDownloadPolicy.hasExplicitIntent(utterance, request)) {
                                sendToolResponse(event.call, "The current spoken request did not directly ask to download this exact URL; no download was started.")
                            } else toolScope.launch {
                                val outcome = try { reviewAndDownload(request).take(1000) }
                                catch (_: Exception) { "The download could not be started; completion is not assumed." }
                                sendToolResponse(event.call, outcome)
                            }
                        }
                        GeminiLiveProtocol.NAVIGATE_TO_TOOL -> {
                            val request = GeminiSafeTools.navigateRequest(event.call.args)
                            if (!GeminiSafeTools.hasExplicitNavigateIntent(utterance, request)) {
                                sendToolResponse(event.call, "The current spoken request did not directly ask for directions to this exact place; no map was opened.")
                            } else toolScope.launch {
                                val outcome = try { reviewAndNavigate(request).take(1000) }
                                catch (_: Exception) { "The map handoff could not be completed; no navigation is assumed." }
                                sendToolResponse(event.call, outcome)
                            }
                        }
                        GeminiLiveProtocol.SET_ALARM_TOOL -> {
                            val request = GeminiAlarmPolicy.request(event.call.args)
                            val result = if (request == null || !GeminiAlarmPolicy.hasExplicitIntent(utterance, request)) {
                                "The current spoken request did not directly ask for this exact one-off alarm time; no Clock handoff was started."
                            } else null
                            if (result != null) sendToolResponse(event.call, result)
                            else toolScope.launch {
                                val outcome = try { reviewAndSetAlarm(request!!).take(1000) }
                                catch (_: Exception) { "The alarm handoff could not be completed; no success is assumed." }
                                sendToolResponse(event.call, outcome)
                            }
                        }
                        GeminiLiveProtocol.TORCH_TOOL -> {
                            val request = GeminiSafeTools.torchRequest(event.call.args)
                            val result = if (!GeminiLiveActionPolicy.hasExplicitTorchIntent(utterance, request.on)) {
                                "The current spoken request did not directly ask for this flashlight direction; no change was made."
                            } else null
                            if (result != null) sendToolResponse(event.call, result)
                            else toolScope.launch {
                                val outcome = try { reviewAndSetTorch(request).take(1000) }
                                catch (_: Exception) { "The flashlight change could not be completed; no success is assumed." }
                                sendToolResponse(event.call, outcome)
                            }
                        }
                        else -> sendToolResponse(event.call, "Unsupported Live tool; no device action was taken.")
                    }
                }
            }
            is GeminiLiveEvent.OutputTranscript -> {
                flushTranscript(user = true)
                synchronized(modelText) { appendBounded(modelText, event.text) }
            }
            is GeminiLiveEvent.Audio -> {
                flushTranscript(user = true)
                queuePlaybackState(event.pcm.size)
                micGate.queueOutput(event.pcm.size, System.nanoTime())
                playAudio(event.pcm)
            }
            GeminiLiveEvent.Interrupted -> {
                clearPlaybackState()
                micGate.clear()
                try { player?.pause(); player?.flush(); player?.play() } catch (_: Exception) { }
                postStatus("Listening · tap Stop to end")
            }
            GeminiLiveEvent.TurnComplete -> {
                flushTranscript(user = true)
                flushTranscript(user = false)
                toolAttemptedThisTurn = false
                if (!isPlaybackSpeaking()) postStatus("Listening · tap Stop to end")
            }
            is GeminiLiveEvent.ServerError -> fail(event.message)
            }
        }
    }

    /** Keep the orb in speaking state through queued PCM, then return to listening as the source UI does. */
    private fun queuePlaybackState(pcmBytes: Int) {
        val now = SystemClock.elapsedRealtimeNanos()
        val generation: Long
        val delayMillis: Long
        val speaking: Boolean
        synchronized(playbackLock) {
            playbackTimeline.enqueue(now, pcmBytes)
            playbackGeneration += 1
            generation = playbackGeneration
            speaking = playbackTimeline.isSpeaking(now)
            delayMillis = playbackTimeline.millisUntilQuiet(now)
            playbackIdleRunnable?.let(mainHandler::removeCallbacks)
            playbackIdleRunnable = null
            if (delayMillis > 0L) {
                val idle = Runnable { settlePlaybackState(generation) }
                playbackIdleRunnable = idle
                mainHandler.postDelayed(idle, delayMillis)
            }
        }
        if (speaking) postStatus("MYRA is speaking…")
    }

    private fun settlePlaybackState(generation: Long) {
        val delayMillis: Long
        synchronized(playbackLock) {
            if (generation != playbackGeneration || closed) return
            delayMillis = playbackTimeline.millisUntilQuiet(SystemClock.elapsedRealtimeNanos())
            if (delayMillis > 0L) {
                val idle = Runnable { settlePlaybackState(generation) }
                playbackIdleRunnable = idle
                mainHandler.postDelayed(idle, delayMillis)
                return
            }
            playbackTimeline.clear()
            playbackIdleRunnable = null
        }
        if (!closed) onStatus("Listening · tap Stop to end")
    }

    private fun isPlaybackSpeaking(): Boolean = synchronized(playbackLock) {
        playbackTimeline.isSpeaking(SystemClock.elapsedRealtimeNanos())
    }

    private fun clearPlaybackState() {
        synchronized(playbackLock) {
            playbackGeneration += 1
            playbackIdleRunnable?.let(mainHandler::removeCallbacks)
            playbackIdleRunnable = null
            playbackTimeline.clear()
        }
    }

    private fun sendToolResponse(call: GeminiLiveToolCall, result: String) {
        if (closed) return
        val sent = try { socket?.send(GeminiLiveProtocol.toolResponseMessage(call, result)) ?: false }
        catch (_: Exception) { false }
        if (!sent) fail("Could not return the device-tool result to Gemini Live.")
    }

    private fun startAudio() {
        if (closed || recording) return
        audioExecutor.execute {
            val minimum = AudioRecord.getMinBufferSize(
                GeminiLiveProtocol.INPUT_SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
            )
            if (minimum <= 0) { fail("Android could not prepare microphone audio."); return@execute }
            val bufferBytes = maxOf(minimum * 2, 8192)
            val audioRecord = try {
                AudioRecord(
                    MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                    GeminiLiveProtocol.INPUT_SAMPLE_RATE,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    bufferBytes,
                )
            } catch (_: Exception) { null }
            if (audioRecord == null || audioRecord.state != AudioRecord.STATE_INITIALIZED) {
                audioRecord?.release()
                fail("Android could not start microphone capture. Check microphone permission and device availability.")
                return@execute
            }
            recorder = audioRecord
            var effects: GeminiLiveAudioEffects.Active? = null
            try {
                audioRecord.startRecording()
                if (audioRecord.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
                    fail("Android did not start microphone capture.")
                    return@execute
                }
                // Match the prototype's echoCancellation/noiseSuppression/autoGainControl
                // request where Android exposes an effect for this capture session.
                effects = GeminiLiveAudioEffects.attach(audioRecord.audioSessionId)
                recording = true
                val samples = ShortArray(GeminiLiveProtocol.INPUT_SAMPLES_PER_CHUNK)
                while (recording && !closed) {
                    val count = audioRecord.read(samples, 0, samples.size, AudioRecord.READ_BLOCKING)
                    if (count < 0) throw IOException("Android microphone read failed.")
                    if (count == 0) continue
                    // Keep draining AudioRecord to avoid capture overruns, but do not send MYRA's
                    // expected playback back into Live as microphone input.
                    if (!micGate.shouldSendMicrophone(System.nanoTime())) continue
                    val bytes = GeminiLiveProtocol.pcm16LittleEndian(samples, count)
                    val sent = socket?.send(GeminiLiveProtocol.audioMessage(bytes)) ?: false
                    if (!sent) throw IOException("Gemini Live connection closed while sending microphone audio.")
                }
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
            } catch (error: Exception) {
                if (!closed) fail(error.message ?: "Microphone streaming stopped unexpectedly.")
            } finally {
                recording = false
                try { if (audioRecord.recordingState == AudioRecord.RECORDSTATE_RECORDING) audioRecord.stop() } catch (_: Exception) { }
                effects?.close()
                audioRecord.release()
                if (recorder === audioRecord) recorder = null
            }
        }
    }

    private fun playAudio(pcm: ByteArray) {
        if (closed || pcm.isEmpty()) return
        playerExecutor.execute {
            try {
                val track = player ?: run {
                    val minBytes = AudioTrack.getMinBufferSize(
                        GeminiLiveProtocol.OUTPUT_SAMPLE_RATE,
                        AudioFormat.CHANNEL_OUT_MONO,
                        AudioFormat.ENCODING_PCM_16BIT,
                    )
                    if (minBytes <= 0) throw IOException("Android could not prepare audio playback.")
                    AudioTrack.Builder()
                        .setAudioFormat(AudioFormat.Builder()
                            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                            .setSampleRate(GeminiLiveProtocol.OUTPUT_SAMPLE_RATE)
                            .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                            .build())
                        .setBufferSizeInBytes(maxOf(minBytes * 2, pcm.size * 2))
                        .build().also { created ->
                            if (created.state != AudioTrack.STATE_INITIALIZED) {
                                created.release()
                                throw IOException("Android could not initialize audio playback.")
                            }
                            player = created
                            created.play()
                        }
                }
                var offset = 0
                while (!closed && offset < pcm.size) {
                    val written = track.write(pcm, offset, pcm.size - offset, AudioTrack.WRITE_BLOCKING)
                    if (written < 0) throw IOException("Android audio playback failed.")
                    if (written == 0) break
                    offset += written
                }
            } catch (error: Exception) {
                if (!closed) postError(error.message ?: "Android audio playback failed.")
            }
        }
    }

    private fun flushTranscript(user: Boolean) {
        val buffer = if (user) userText else modelText
        val text = synchronized(buffer) {
            val value = buffer.toString().trim().take(8000)
            buffer.clear()
            value
        }
        if (text.isNotBlank()) mainHandler.post { if (!closed) onTranscript(user, text) }
    }

    private fun appendBounded(buffer: StringBuilder, value: String) = synchronized(buffer) {
        if (buffer.length < 8000) buffer.append(value.take(8000 - buffer.length))
    }

    private fun fail(message: String) {
        if (closed) return
        postError(message.take(240))
        close()
    }

    private fun postStatus(value: String) = mainHandler.post { if (!closed) onStatus(value) }
    private fun postError(value: String) = mainHandler.post { onError(value) }

    private fun stopAudio() {
        clearPlaybackState()
        recording = false
        try { recorder?.stop() } catch (_: Exception) { }
        playerExecutor.execute { try { player?.pause(); player?.flush() } catch (_: Exception) { } }
    }

    fun close() {
        if (closed) return
        closed = true
        synchronized(reconnectLock) {
            reconnectScheduled = false
            reconnectRunnable?.let(mainHandler::removeCallbacks)
            reconnectRunnable = null
            resumption.clear()
        }
        toolScope.cancel()
        stopAudio()
        tokenCall?.cancel()
        tokenCall = null
        socket?.close(1000, "User stopped live voice")
        tokenClient.dispatcher.cancelAll()
        tokenClient.dispatcher.executorService.shutdown()
        tokenClient.connectionPool.evictAll()
        socket = null
        playerExecutor.execute { try { player?.release() } catch (_: Exception) { }; player = null }
        client.dispatcher.executorService.shutdown()
        client.connectionPool.evictAll()
    }
}
