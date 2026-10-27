package com.myra.ultra.nativeapp

import java.io.IOException
import okio.ByteString
import okio.ByteString.Companion.decodeBase64
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

internal data class GeminiLiveToolCall(val id: String, val name: String, val args: JSONObject)

internal sealed class GeminiLiveEvent {
    data object SetupComplete : GeminiLiveEvent()
    data class InputTranscript(val text: String) : GeminiLiveEvent()
    data class OutputTranscript(val text: String) : GeminiLiveEvent()
    data class Audio(val pcm: ByteArray) : GeminiLiveEvent()
    data class ToolCall(val call: GeminiLiveToolCall) : GeminiLiveEvent()
    data object Interrupted : GeminiLiveEvent()
    data object TurnComplete : GeminiLiveEvent()
    data class ServerError(val message: String) : GeminiLiveEvent()
    data class SessionResumptionUpdate(val resumable: Boolean, val newHandle: String?) : GeminiLiveEvent()
    data class GoAway(val timeLeftMillis: Long) : GeminiLiveEvent()
}

/** Bounded JSON/audio framing for Gemini's documented Live API WebSocket protocol. */
internal object GeminiLiveProtocol {
    const val MODEL = "gemini-3.8-live"
    const val BATTERY_STATUS_TOOL = "battery_status" // Exact read-only function name from the Python prototype.
    const val SET_VOLUME_TOOL = "set_volume"
    const val SET_BRIGHTNESS_TOOL = GeminiSafeTools.SET_BRIGHTNESS
    const val TORCH_TOOL = "torch"
    const val SHARE_LOCATION_TOOL = GeminiLocationSharePolicy.TOOL
    const val SHOW_TOAST_TOOL = GeminiToastPolicy.TOOL
    const val SET_TIMER_TOOL = GeminiTimerPolicy.TOOL
    const val SET_ALARM_TOOL = GeminiAlarmPolicy.TOOL
    const val NAVIGATE_TO_TOOL = "navigate_to"
    const val DOWNLOAD_FILE_TOOL = GeminiDownloadPolicy.TOOL
    const val INPUT_SAMPLE_RATE = 16_000
    const val OUTPUT_SAMPLE_RATE = 24_000
    const val INPUT_SAMPLES_PER_CHUNK = 4096 // 256 ms mono PCM
    const val MAX_MESSAGE_CHARS = 1_500_000
    const val MAX_AUDIO_BYTES = 1_000_000
    const val MAX_SESSION_HANDLE_CHARS = 4096

    fun setupMessage(systemInstruction: String, resumptionHandle: String? = null): String {
        val resumption = JSONObject()
        if (!resumptionHandle.isNullOrBlank()) {
            if (resumptionHandle.length > MAX_SESSION_HANDLE_CHARS || resumptionHandle.any(Char::isISOControl)) {
                throw IOException("Invalid Gemini Live resumption handle.")
            }
            resumption.put("handle", resumptionHandle)
        }
        return JSONObject()
        .put("setup", JSONObject()
            .put("model", "models/$MODEL")
            .put("responseModalities", org.json.JSONArray().put("AUDIO"))
            .put("speechConfig", JSONObject().put("voiceConfig", JSONObject().put("prebuiltVoiceConfig", JSONObject().put("voiceName", "Aoede"))))
            .put("inputAudioTranscription", JSONObject())
            .put("outputAudioTranscription", JSONObject())
            .put("systemInstruction", JSONObject().put("parts", JSONArray().put(JSONObject().put("text", systemInstruction.take(4000)))))
            .put("tools", JSONArray().put(liveToolsDeclaration()))
            .put("sessionResumption", resumption))
        .toString()
    }

    fun liveToolsDeclaration(): JSONObject {
        val declarations = JSONArray()
            .put(JSONObject()
                .put("name", BATTERY_STATUS_TOOL)
                .put("description", "Read the current phone battery percentage and charging state only when the user directly asks about battery status. This is read-only.")
                .put("parameters", JSONObject().put("type", "OBJECT").put("properties", JSONObject())))
            .put(JSONObject()
                .put("name", SET_VOLUME_TOOL)
                .put("description", "Request one exact phone volume level only when the user directly speaks a stream and exact percentage. MYRA requires native approval before changing it.")
                .put("parameters", JSONObject().put("type", "OBJECT")
                    .put("properties", JSONObject()
                        .put("stream", JSONObject().put("type", "STRING").put("enum", JSONArray().put("music").put("ring").put("alarm").put("notification").put("system").put("call")))
                        .put("percent", JSONObject().put("type", "INTEGER").put("minimum", 0).put("maximum", 100)))
                    .put("required", JSONArray().put("stream").put("percent"))))
            .put(JSONObject()
                .put("name", SET_BRIGHTNESS_TOOL)
                .put("description", "Request one exact 0–255 brightness level only when the user directly speaks the level. MYRA requires native approval and changes only its own app window, never device-wide brightness.")
                .put("parameters", JSONObject().put("type", "OBJECT")
                    .put("properties", JSONObject().put("level", JSONObject().put("type", "INTEGER").put("minimum", MyraWindowBrightness.MIN_LEVEL).put("maximum", MyraWindowBrightness.MAX_LEVEL)))
                    .put("required", JSONArray().put("level"))))
            .put(JSONObject()
                .put("name", SET_TIMER_TOOL)
                .put("description", "Request one timer for the exact duration in a direct current spoken request (1 second to 24 hours). MYRA requires native approval and opens Android Clock; it cannot confirm the timer was started.")
                .put("parameters", JSONObject().put("type", "OBJECT")
                    .put("properties", JSONObject().put("seconds", JSONObject().put("type", "INTEGER").put("minimum", ClockTimerData.MIN_SECONDS).put("maximum", ClockTimerData.MAX_SECONDS)))
                    .put("required", JSONArray().put("seconds"))))
            .put(JSONObject()
                .put("name", SET_ALARM_TOOL)
                .put("description", "Request one alarm at the exact 24-hour time in a direct current spoken request. MYRA requires native approval and opens Android Clock; the user must confirm it there and MYRA cannot verify it was saved.")
                .put("parameters", JSONObject().put("type", "OBJECT")
                    .put("properties", JSONObject()
                        .put("hour", JSONObject().put("type", "INTEGER").put("minimum", 0).put("maximum", 23))
                        .put("minute", JSONObject().put("type", "INTEGER").put("minimum", 0).put("maximum", 59)))
                    .put("required", JSONArray().put("hour").put("minute"))))
            .put(JSONObject()
                .put("name", NAVIGATE_TO_TOOL)
                .put("description", "Request one Android Maps search only when the user directly asks for directions to this exact place in the current spoken request. MYRA requires native approval; this opens a destination search but does not start or verify navigation.")
                .put("parameters", JSONObject().put("type", "OBJECT")
                    .put("properties", JSONObject().put("place", JSONObject().put("type", "STRING").put("minLength", 1).put("maxLength", MapsDestinationData.MAX_LENGTH)))
                    .put("required", JSONArray().put("place"))))
            .put(JSONObject()
                .put("name", TORCH_TOOL)
                .put("description", "Request flashlight on or off only when the user directly asks for that exact direction. MYRA requires native approval first; Camera permission is requested only after approval to turn on, and success requires Android confirmation.")
                .put("parameters", JSONObject().put("type", "OBJECT")
                    .put("properties", JSONObject().put("on", JSONObject().put("type", "BOOLEAN")))
                    .put("required", JSONArray().put("on"))))
            .put(JSONObject()
                .put("name", SHOW_TOAST_TOOL)
                .put("description", "Request one brief in-app toast with the exact text from the direct spoken user request. MYRA requires native approval before displaying it; this is not a notification and is not saved.")
                .put("parameters", JSONObject().put("type", "OBJECT")
                    .put("properties", JSONObject().put("text", JSONObject().put("type", "STRING").put("minLength", 1).put("maxLength", 120)))
                    .put("required", JSONArray().put("text"))))
            .put(JSONObject()
                .put("name", SHARE_LOCATION_TOOL)
                .put("description", "Share one rounded approximate current location with Google only when the user directly asks where they are. Android coarse-location permission and a separate native review are required; no location is retained.")
                .put("parameters", JSONObject().put("type", "OBJECT").put("properties", JSONObject())))
            .put(JSONObject()
                .put("name", DOWNLOAD_FILE_TOOL)
                .put("description", "Request one download only for an exact HTTP(S) URL in the direct current spoken request. MYRA validates and previews the URL and filename for native approval before starting Android Download Manager; it may use network data and incur charges, and completion is not verified.")
                .put("parameters", JSONObject().put("type", "OBJECT")
                    .put("properties", JSONObject().put("url", JSONObject().put("type", "STRING").put("minLength", 1).put("maxLength", 2048)))
                    .put("required", JSONArray().put("url"))))
        return JSONObject().put("functionDeclarations", declarations)
    }

    fun toolResponseMessage(call: GeminiLiveToolCall, result: String): String {
        if (call.id.isBlank() || call.id.length > 256 || call.id.any(Char::isISOControl)) {
            throw IOException("Invalid Gemini Live function response target.")
        }
        try {
            when (call.name) {
                BATTERY_STATUS_TOOL -> if (call.args.length() != 0) throw IOException("Unexpected battery arguments.")
                SET_VOLUME_TOOL -> GeminiSafeTools.volumeRequest(call.args)
                SET_BRIGHTNESS_TOOL -> GeminiSafeTools.brightnessRequest(call.args)
                SET_TIMER_TOOL -> GeminiTimerPolicy.request(call.args) ?: throw IOException("Invalid timer request.")
                SET_ALARM_TOOL -> GeminiAlarmPolicy.request(call.args) ?: throw IOException("Invalid alarm request.")
                NAVIGATE_TO_TOOL -> GeminiSafeTools.navigateRequest(call.args)
                DOWNLOAD_FILE_TOOL -> GeminiDownloadPolicy.request(call.args)
                TORCH_TOOL -> GeminiSafeTools.torchRequest(call.args)
                SHARE_LOCATION_TOOL -> GeminiLocationSharePolicy.validateArguments(call.args)
                SHOW_TOAST_TOOL -> GeminiToastPolicy.request(call.args)
                else -> throw IOException("Unsupported Live tool.")
            }
        } catch (_: Exception) {
            throw IOException("Invalid Gemini Live function response target.")
        }
        return JSONObject().put("toolResponse", JSONObject().put("functionResponses", JSONArray().put(JSONObject()
            .put("id", call.id)
            .put("name", call.name)
            .put("response", JSONObject().put("result", result.take(4000)))))).toString()
    }

    fun audioMessage(pcm: ByteArray): String {
        if (pcm.isEmpty() || pcm.size > MAX_AUDIO_BYTES || pcm.size % 2 != 0) throw IOException("Invalid live audio chunk size.")
        return JSONObject().put("realtimeInput", JSONObject().put("audio", JSONObject()
            .put("mimeType", "audio/pcm;rate=$INPUT_SAMPLE_RATE")
            .put("data", ByteString.of(*pcm).base64()))).toString()
    }

    fun pcm16LittleEndian(samples: ShortArray, count: Int): ByteArray {
        if (count < 0 || count > samples.size) throw IOException("Invalid microphone sample count.")
        val bytes = ByteArray(count * 2)
        for (index in 0 until count) {
            val sample = samples[index].toInt()
            bytes[index * 2] = (sample and 0xff).toByte()
            bytes[index * 2 + 1] = ((sample ushr 8) and 0xff).toByte()
        }
        return bytes
    }

    fun parseServerMessage(message: String): List<GeminiLiveEvent> {
        if (message.length > MAX_MESSAGE_CHARS) throw IOException("Gemini Live returned an oversized message.")
        val json = try { JSONObject(message) } catch (error: JSONException) {
            throw IOException("Gemini Live returned invalid JSON.", error)
        }
        json.optJSONObject("error")?.let { error ->
            val code = error.optInt("code", -1)
            throw IOException("Gemini Live request failed${if (code >= 0) " (HTTP $code)" else ""}. Check API key, model access and quota.")
        }
        if (json.optJSONObject("setupComplete") != null) return listOf(GeminiLiveEvent.SetupComplete)
        val events = mutableListOf<GeminiLiveEvent>()
        json.optJSONObject("sessionResumptionUpdate")?.let { update ->
            val resumable = update.optBoolean("resumable", false)
            val rawHandle = update.optString("newHandle").takeIf { it != "null" }
            val handle = rawHandle?.takeIf {
                it.isNotBlank() && it.length <= MAX_SESSION_HANDLE_CHARS && !it.any(Char::isISOControl)
            }
            events += GeminiLiveEvent.SessionResumptionUpdate(resumable, handle)
        }
        json.optJSONObject("goAway")?.let { goAway ->
            events += GeminiLiveEvent.GoAway(parseGoAwayTimeLeft(goAway.optString("timeLeft")))
        }
        json.optJSONObject("toolCall")?.let { toolCall ->
            val calls = toolCall.optJSONArray("functionCalls")
                ?: throw IOException("Gemini Live returned a malformed function call; no device data was read.")
            if (calls.length() != 1) throw IOException("Gemini Live requested multiple functions; no device data was read.")
            val raw = calls.optJSONObject(0)
                ?: throw IOException("Gemini Live returned a malformed function call; no device data was read.")
            val id = raw.optString("id").trim()
            val name = raw.optString("name").trim()
            val args = raw.optJSONObject("args") ?: JSONObject()
            if (id.isEmpty() || id.length > 256 || id.any(Char::isISOControl)) {
                throw IOException("Gemini Live requested an unsupported or malformed tool; no device data was read.")
            }
            try {
                when (name) {
                    BATTERY_STATUS_TOOL -> if (args.length() != 0) throw IOException("Unexpected battery arguments.")
                    SET_VOLUME_TOOL -> GeminiSafeTools.volumeRequest(args)
                    SET_BRIGHTNESS_TOOL -> GeminiSafeTools.brightnessRequest(args)
                    SET_TIMER_TOOL -> GeminiTimerPolicy.request(args) ?: throw IOException("Invalid timer request.")
                    SET_ALARM_TOOL -> GeminiAlarmPolicy.request(args) ?: throw IOException("Invalid alarm request.")
                    NAVIGATE_TO_TOOL -> GeminiSafeTools.navigateRequest(args)
                    DOWNLOAD_FILE_TOOL -> GeminiDownloadPolicy.request(args)
                    TORCH_TOOL -> GeminiSafeTools.torchRequest(args)
                    SHARE_LOCATION_TOOL -> GeminiLocationSharePolicy.validateArguments(args)
                    SHOW_TOAST_TOOL -> GeminiToastPolicy.request(args)
                    else -> throw IOException("Unsupported Live tool.")
                }
            } catch (_: Exception) {
                throw IOException("Gemini Live requested an unsupported or malformed tool; no device action was taken.")
            }
            events += GeminiLiveEvent.ToolCall(GeminiLiveToolCall(id, name, args))
        }
        val content = json.optJSONObject("serverContent") ?: return events
        content.optJSONObject("inputTranscription")?.optString("text")
            ?.takeIf { it.isNotBlank() && it != "null" }?.let { events += GeminiLiveEvent.InputTranscript(it.take(8000)) }
        content.optJSONObject("outputTranscription")?.optString("text")
            ?.takeIf { it.isNotBlank() && it != "null" }?.let { events += GeminiLiveEvent.OutputTranscript(it.take(8000)) }
        if (content.optBoolean("interrupted")) events += GeminiLiveEvent.Interrupted
        val parts = content.optJSONObject("modelTurn")?.optJSONArray("parts")
        if (parts != null) for (index in 0 until parts.length()) {
            val inline = parts.optJSONObject(index)?.optJSONObject("inlineData") ?: continue
            if (!inline.optString("mimeType").startsWith("audio/pcm")) continue
            val encoded = inline.optString("data")
            val decoded = try { encoded.decodeBase64()?.toByteArray() ?: throw IllegalArgumentException("Invalid base64") } catch (error: IllegalArgumentException) {
                throw IOException("Gemini Live returned invalid audio data.", error)
            }
            if (decoded.isEmpty() || decoded.size > MAX_AUDIO_BYTES || decoded.size % 2 != 0) {
                throw IOException("Gemini Live returned an invalid audio chunk size.")
            }
            events += GeminiLiveEvent.Audio(decoded)
        }
        if (content.optBoolean("turnComplete")) events += GeminiLiveEvent.TurnComplete
        return events
    }

    /** GoAway.timeLeft uses the protobuf JSON Duration form, such as "30s". */
    private fun parseGoAwayTimeLeft(value: String): Long {
        if (value.isBlank() || value.length > 64) return 0L
        val protobufDuration = Regex("^(\\d+(?:\\.\\d{1,9})?)s$").matchEntire(value)
        if (protobufDuration != null) {
            return try {
                java.math.BigDecimal(protobufDuration.groupValues[1])
                    .movePointRight(3).toLong().coerceIn(0L, 120_000L)
            } catch (_: Exception) {
                0L
            }
        }
        // Be tolerant of an ISO-8601 duration if a gateway normalizes the protobuf value.
        return try {
            java.time.Duration.parse(value).toMillis().coerceIn(0L, 120_000L)
        } catch (_: Exception) {
            0L
        }
    }
}
