package com.myra.ultra.nativeapp

import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okio.Buffer
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.TimeUnit

/** Native-only HTTPS client. It never places pairing codes or bearer tokens in URLs or logs. */
class ScreenShareNetwork {
    private val client = OkHttpClient.Builder()
        .connectTimeout(8, TimeUnit.SECONDS)
        .readTimeout(12, TimeUnit.SECONDS)
        .writeTimeout(12, TimeUnit.SECONDS)
        .callTimeout(20, TimeUnit.SECONDS)
        .pingInterval(10, TimeUnit.SECONDS)
        .followRedirects(false)
        .followSslRedirects(false)
        .build()

    fun redeemPairing(serviceUrl: String, invitation: ScreenShareInvitation): ScreenShareCredentials {
        val body = JSONObject()
            .put("pairing_id", invitation.pairingId)
            .put("pairing_code", invitation.pairingCode)
            .put("sender_label", "MYRA on this device")
        val result = executeJson(serviceUrl, "/screen-share/pairings/redeem", null, body)
        val id = result.optString("pairing_id")
        val token = result.optString("sender_token")
        val lifetime = result.optLong("sender_token_expires_in_seconds", -1)
        if (!ScreenShareProtocol.isValidPairingId(id) || id != invitation.pairingId ||
            token.length !in 32..128 || lifetime !in 1..(30L * 24 * 60 * 60)) {
            throw IOException("Personal AI returned an invalid pairing response.")
        }
        return ScreenShareCredentials(ScreenShareProtocol.normalizeServiceUrl(serviceUrl), id, token)
    }

    fun requestSession(credentials: ScreenShareCredentials): String {
        val result = executeJson(
            credentials.serviceUrl,
            "/screen-share/sessions",
            credentials.senderToken,
            JSONObject().put("pairing_id", credentials.pairingId),
        )
        val id = result.optString("session_id")
        if (!ScreenShareProtocol.isValidSessionId(id) || result.optString("state") != "awaiting_receiver_approval") {
            throw IOException("Personal AI returned an invalid screen-share request.")
        }
        return id
    }

    fun sessionStatus(credentials: ScreenShareCredentials, sessionId: String): String {
        require(ScreenShareProtocol.isValidSessionId(sessionId)) { "Invalid screen-share session." }
        val result = executeJson(
            credentials.serviceUrl,
            "/screen-share/sessions/$sessionId/status",
            credentials.senderToken,
            null,
        )
        if (result.optString("session_id") != sessionId) {
            throw IOException("Personal AI returned a status for a different session.")
        }
        val state = result.optString("state")
        if (state !in setOf("awaiting_receiver_approval", "approved", "active", "stopped", "expired", "revoked")) {
            throw IOException("Personal AI returned an unknown session state.")
        }
        return state
    }

    fun endSession(credentials: ScreenShareCredentials, sessionId: String) {
        require(ScreenShareProtocol.isValidSessionId(sessionId)) { "Invalid screen-share session." }
        executeJson(credentials.serviceUrl, "/screen-share/sessions/$sessionId/end", credentials.senderToken, JSONObject())
    }

    fun streamRequest(credentials: ScreenShareCredentials, sessionId: String): Request {
        val url = ScreenShareProtocol.streamUrl(credentials.serviceUrl, sessionId)
        return Request.Builder()
            .url(url)
            .header("Authorization", "Bearer ${credentials.senderToken}")
            .header("Cache-Control", "no-store")
            .build()
    }

    fun openStream(credentials: ScreenShareCredentials, sessionId: String, listener: okhttp3.WebSocketListener): okhttp3.WebSocket =
        client.newWebSocket(streamRequest(credentials, sessionId), listener)

    private fun executeJson(serviceUrl: String, path: String, token: String?, body: JSONObject?): JSONObject {
        val base = ScreenShareProtocol.normalizeServiceUrl(serviceUrl)
        val requestBody = body?.toString()?.toRequestBody(JSON_MEDIA_TYPE)
        val builder = Request.Builder()
            .url("$base$path")
            .header("Accept", "application/json")
            .header("Cache-Control", "no-store")
        if (token != null) builder.header("Authorization", "Bearer $token")
        if (body != null) builder.post(requestBody!!) else builder.get()
        val response = client.newCall(builder.build()).execute()
        return response.use(::readJsonResponse)
    }

    private fun readJsonResponse(response: Response): JSONObject {
        if (!response.isSuccessful) throw IOException("Personal AI request failed (HTTP ${response.code}).")
        val body = response.body ?: throw IOException("Personal AI returned an empty response.")
        val declared = body.contentLength()
        if (declared > MAX_JSON_RESPONSE_BYTES) throw IOException("Personal AI returned an oversized response.")
        val source = body.source()
        val buffer = Buffer()
        while (true) {
            val read = source.read(buffer, 8 * 1024L)
            if (read == -1L) break
            if (buffer.size > MAX_JSON_RESPONSE_BYTES) throw IOException("Personal AI returned an oversized response.")
        }
        return try {
            JSONObject(buffer.readUtf8())
        } catch (_: Exception) {
            throw IOException("Personal AI returned an invalid response.")
        }
    }

    companion object {
        private val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
        private const val MAX_JSON_RESPONSE_BYTES = 64 * 1024L
    }
}
