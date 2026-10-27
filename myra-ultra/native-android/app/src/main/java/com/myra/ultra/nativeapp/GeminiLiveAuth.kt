package com.myra.ultra.nativeapp

import java.io.IOException
import java.util.concurrent.TimeUnit
import okhttp3.HttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONException
import org.json.JSONObject

/** Creates a one-use, short-lived Gemini Live token without putting the durable key in the socket URL. */
internal object GeminiLiveAuth {
    private const val TOKEN_ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/auth_tokens"
    private const val LIVE_HOST = "generativelanguage.googleapis.com"
    private const val LIVE_PATH = "ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContentConstrained"
    const val TOKEN_TTL_MS = 30 * 60 * 1000L
    const val SESSION_START_TTL_MS = 60 * 1000L
    const val MAX_RESPONSE_BYTES = 64 * 1024L
    private val JSON = "application/json; charset=utf-8".toMediaType()

    class TokenRequest internal constructor(
        val request: Request,
        val expiresAtMillis: Long,
        val startExpiresAtMillis: Long,
    )

    /** Secret token intentionally is not a data class, to avoid accidental value-bearing toString output. */
    class EphemeralToken internal constructor(
        internal val value: String,
        val expiresAtMillis: Long,
        val startExpiresAtMillis: Long,
    ) {
        fun isExpired(nowMillis: Long): Boolean = nowMillis >= expiresAtMillis
        fun canStartSession(nowMillis: Long): Boolean = nowMillis < startExpiresAtMillis && !isExpired(nowMillis)
    }

    fun createTokenRequest(apiKey: String, systemInstruction: String, nowMillis: Long = System.currentTimeMillis()): TokenRequest {
        if (apiKey.isBlank() || apiKey.length > 4096) throw IOException("A valid Gemini API key is required for Live voice.")
        val setup = try { JSONObject(GeminiLiveProtocol.setupMessage(systemInstruction)).getJSONObject("setup") }
        catch (error: JSONException) { throw IOException("Could not prepare Gemini Live setup.", error) }
        val model = setup.optString("model")
        if (model != "models/${GeminiLiveProtocol.MODEL}") throw IOException("Unexpected Gemini Live model configuration.")
        setup.remove("model")
        val expiresAt = nowMillis + TOKEN_TTL_MS
        val startExpiresAt = nowMillis + SESSION_START_TTL_MS
        val requestBody = JSONObject()
            .put("uses", 1)
            .put("expireTime", formatRfc3339(expiresAt))
            .put("newSessionExpireTime", formatRfc3339(startExpiresAt))
            .put("liveConnectConstraints", JSONObject()
                .put("model", GeminiLiveProtocol.MODEL)
                .put("config", setup))
            .toString()
            .toRequestBody(JSON)
        val request = Request.Builder()
            .url(TOKEN_ENDPOINT)
            .header("x-goog-api-key", apiKey)
            .post(requestBody)
            .build()
        return TokenRequest(request, expiresAt, startExpiresAt)
    }

    fun parseTokenResponse(
        httpCode: Int,
        responseBody: String,
        requested: TokenRequest,
        nowMillis: Long = System.currentTimeMillis(),
    ): EphemeralToken {
        if (responseBody.length > MAX_RESPONSE_BYTES) throw IOException("Gemini Live token response was oversized.")
        if (nowMillis >= requested.startExpiresAtMillis) throw IOException("The Gemini Live token expired before connecting. Start live voice again.")
        if (httpCode !in 200..299) {
            val reason = when (httpCode) {
                401, 403 -> "Gemini did not authorize a Live token. Check API key access and Live API availability."
                429 -> "Gemini Live token creation is rate-limited or out of quota. Try again later."
                else -> "Gemini Live token creation failed (HTTP $httpCode). Check connection and API access."
            }
            throw IOException(reason)
        }
        val name = try { JSONObject(responseBody).optString("name").trim() }
        catch (error: JSONException) { throw IOException("Gemini returned an invalid Live token response.", error) }
        if (name.isEmpty() || name.length > 4096 || name.any { it.isWhitespace() || it.isISOControl() }) {
            throw IOException("Gemini returned an invalid Live token.")
        }
        return EphemeralToken(name, requested.expiresAtMillis, requested.startExpiresAtMillis)
    }

    fun liveWebSocketUrl(token: EphemeralToken, nowMillis: Long = System.currentTimeMillis()): HttpUrl {
        if (!token.canStartSession(nowMillis)) throw IOException("The Gemini Live token expired before connecting. Start live voice again.")
        return HttpUrl.Builder()
            .scheme("https")
            .host(LIVE_HOST)
            .addPathSegments(LIVE_PATH)
            .addQueryParameter("access_token", token.value)
            .build()
    }

    private fun formatRfc3339(epochMillis: Long): String = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", java.util.Locale.US)
        .apply { timeZone = java.util.TimeZone.getTimeZone("UTC") }
        .format(java.util.Date(epochMillis))
}
