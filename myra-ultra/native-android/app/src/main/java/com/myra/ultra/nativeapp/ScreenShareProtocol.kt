package com.myra.ultra.nativeapp

import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import org.json.JSONObject

/** Values copied from Personal AI's deliberate, one-use pairing screen. */
data class ScreenShareInvitation(val pairingId: String, val pairingCode: String)

data class ScreenShareCredentials(val serviceUrl: String, val pairingId: String, val senderToken: String)

data class ScreenShareFrameSize(val width: Int, val height: Int)

object ScreenShareProtocol {
    const val MAX_FRAME_BYTES = 1_500_000
    const val MAX_FPS = 5
    const val SEND_FPS = 3
    const val MAX_STREAM_SECONDS = 60 * 60
    const val MAX_LONG_EDGE = 1280

    private val idPattern = Regex("^[a-f0-9]{32}$")
    private val codePattern = Regex("^[A-Za-z0-9_-]{32,64}$")
    private val sessionPattern = Regex("^[a-f0-9]{32}$")

    fun normalizeServiceUrl(raw: String): String {
        val candidate = raw.trim().trimEnd('/')
        val url = candidate.toHttpUrlOrNull()
            ?: throw IllegalArgumentException("Enter a complete HTTPS service address.")
        require(url.scheme == "https") { "Screen sharing requires HTTPS; plain HTTP is blocked." }
        require(url.host.isNotBlank() && url.username.isEmpty() && url.password.isEmpty()) {
            "The service address must not contain credentials."
        }
        require(url.encodedQuery == null && url.encodedFragment == null) {
            "The service address must not contain a query or fragment."
        }
        return url.toString().trimEnd('/')
    }

    fun parseInvitation(raw: String): ScreenShareInvitation {
        require(raw.length in 2..512) { "Paste the pairing information copied from Personal AI." }
        val value = try {
            JSONObject(raw.trim())
        } catch (_: Exception) {
            throw IllegalArgumentException("Pairing information must be the JSON copied from Personal AI.")
        }
        val id = value.optString("pairing_id")
        val code = value.optString("pairing_code")
        require(value.length() == 2 && idPattern.matches(id) && codePattern.matches(code)) {
            "Pairing information is incomplete or invalid. Create a fresh code in Personal AI."
        }
        return ScreenShareInvitation(id, code)
    }

    fun isValidPairingId(value: String): Boolean = idPattern.matches(value)

    fun isValidSessionId(value: String): Boolean = sessionPattern.matches(value)

    fun captureSize(screenWidth: Int, screenHeight: Int): ScreenShareFrameSize {
        require(screenWidth > 0 && screenHeight > 0) { "Android returned invalid screen dimensions." }
        val scale = minOf(1.0, MAX_LONG_EDGE.toDouble() / maxOf(screenWidth, screenHeight))
        return ScreenShareFrameSize(
            width = (screenWidth * scale).toInt().coerceAtLeast(1),
            height = (screenHeight * scale).toInt().coerceAtLeast(1),
        )
    }

    fun startMessage(width: Int, height: Int): JSONObject {
        require(width in 1..4096 && height in 1..4096 && width.toLong() * height <= 8_294_400L)
        return JSONObject()
            .put("type", "start")
            .put("media_projection_consent", true)
            .put("foreground_service", true)
            .put("width", width)
            .put("height", height)
            .put("fps", SEND_FPS)
    }

    fun streamUrl(serviceUrl: String, sessionId: String): HttpUrl {
        require(isValidSessionId(sessionId)) { "Invalid screen-share session." }
        val base = normalizeServiceUrl(serviceUrl).toHttpUrlOrNull()
            ?: throw IllegalArgumentException("Enter a complete HTTPS service address.")
        // OkHttp's WebSocket API takes an HTTPS URL and performs the WSS upgrade itself.
        return base.newBuilder()
            .addPathSegments("screen-share/sessions/$sessionId/stream")
            .build()
    }
}
