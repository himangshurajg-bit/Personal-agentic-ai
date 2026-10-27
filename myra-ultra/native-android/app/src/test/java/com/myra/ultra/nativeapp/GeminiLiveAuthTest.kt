package com.myra.ultra.nativeapp

import java.io.IOException
import okhttp3.Request
import okio.Buffer
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class GeminiLiveAuthTest {
    private val now = 1_800_000_000_000L

    private fun request() = GeminiLiveAuth.createTokenRequest("long-lived-secret-key", "Speak briefly", now)

    @Test fun provisionsOneUseTokenWithConstrainedSetupAndKeyOnlyInHttpsHeader() {
        val pending = request()
        val req: Request = pending.request
        assertEquals("https", req.url.scheme)
        assertEquals("generativelanguage.googleapis.com", req.url.host)
        assertEquals("/v1beta/auth_tokens", req.url.encodedPath)
        assertNull(req.url.queryParameter("key"))
        assertFalse(req.url.toString().contains("long-lived-secret-key"))
        assertEquals("long-lived-secret-key", req.header("x-goog-api-key"))
        val buffer = Buffer()
        req.body!!.writeTo(buffer)
        val body = JSONObject(buffer.readUtf8())
        assertEquals(1, body.getInt("uses"))
        assertTrue(body.getString("expireTime").endsWith("Z"))
        assertTrue(body.getString("newSessionExpireTime").endsWith("Z"))
        val constraints = body.getJSONObject("liveConnectConstraints")
        assertEquals(GeminiLiveProtocol.MODEL, constraints.getString("model"))
        val config = constraints.getJSONObject("config")
        assertFalse(config.has("model"))
        assertEquals("AUDIO", config.getJSONArray("responseModalities").getString(0))
        assertEquals("Speak briefly", config.getJSONObject("systemInstruction").getJSONArray("parts").getJSONObject(0).getString("text"))
        val tools = config.getJSONArray("tools")
        assertEquals(1, tools.length())
        val declarations = tools.getJSONObject(0).getJSONArray("functionDeclarations")
        assertEquals(10, declarations.length())
        assertTrue(declarations.getJSONObject(2).getString("description").contains("own app window"))
        assertTrue(declarations.getJSONObject(3).getString("description").contains("24 hours"))
        assertEquals(listOf(GeminiLiveProtocol.BATTERY_STATUS_TOOL, GeminiLiveProtocol.SET_VOLUME_TOOL, GeminiLiveProtocol.SET_BRIGHTNESS_TOOL, GeminiLiveProtocol.SET_TIMER_TOOL, GeminiLiveProtocol.SET_ALARM_TOOL, GeminiLiveProtocol.NAVIGATE_TO_TOOL, GeminiLiveProtocol.TORCH_TOOL, GeminiLiveProtocol.SHOW_TOAST_TOOL, GeminiLiveProtocol.SHARE_LOCATION_TOOL, GeminiLiveProtocol.DOWNLOAD_FILE_TOOL),
            (0 until declarations.length()).map { declarations.getJSONObject(it).getString("name") })
        assertEquals(now + GeminiLiveAuth.TOKEN_TTL_MS, pending.expiresAtMillis)
        assertEquals(now + GeminiLiveAuth.SESSION_START_TTL_MS, pending.startExpiresAtMillis)
    }

    @Test fun parsesTokenAndBuildsConstrainedSocketUrlWithOnlyShortLivedCredential() {
        val pending = request()
        val token = GeminiLiveAuth.parseTokenResponse(200, """{"name":"auth_tokens/short-lived-value"}""", pending, now + 250)
        assertEquals(pending.expiresAtMillis, token.expiresAtMillis)
        assertTrue(token.canStartSession(now + 250))
        val url = GeminiLiveAuth.liveWebSocketUrl(token, now + 250)
        assertEquals("https", url.scheme)
        assertEquals("/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContentConstrained", url.encodedPath)
        assertEquals("auth_tokens/short-lived-value", url.queryParameter("access_token"))
        assertNull(url.queryParameter("key"))
        assertFalse(url.toString().contains("long-lived-secret-key"))
    }

    @Test fun rejectsExpiredTokenAndTokenTooLateToStartSession() {
        val pending = request()
        val token = GeminiLiveAuth.parseTokenResponse(200, """{"name":"short"}""", pending, now)
        assertFalse(token.isExpired(now + GeminiLiveAuth.TOKEN_TTL_MS - 1))
        assertTrue(token.isExpired(now + GeminiLiveAuth.TOKEN_TTL_MS))
        assertFalse(token.canStartSession(now + GeminiLiveAuth.SESSION_START_TTL_MS))
        assertThrowsIOException { GeminiLiveAuth.liveWebSocketUrl(token, now + GeminiLiveAuth.SESSION_START_TTL_MS) }
        assertThrowsIOException {
            GeminiLiveAuth.parseTokenResponse(200, """{"name":"short"}""", pending, now + GeminiLiveAuth.SESSION_START_TTL_MS)
        }
    }

    @Test fun rejectsProviderErrorsAndMalformedOrMissingToken() {
        val pending = request()
        assertThrowsIOException { GeminiLiveAuth.parseTokenResponse(403, "{}", pending, now) }
        assertThrowsIOException { GeminiLiveAuth.parseTokenResponse(429, "{}", pending, now) }
        assertThrowsIOException { GeminiLiveAuth.parseTokenResponse(503, "{}", pending, now) }
        assertThrowsIOException { GeminiLiveAuth.parseTokenResponse(200, "not-json", pending, now) }
        assertThrowsIOException { GeminiLiveAuth.parseTokenResponse(200, "{}", pending, now) }
        assertThrowsIOException { GeminiLiveAuth.parseTokenResponse(200, """{"name":"bad token"}""", pending, now) }
        assertThrowsIOException { GeminiLiveAuth.parseTokenResponse(200, "x".repeat(GeminiLiveAuth.MAX_RESPONSE_BYTES.toInt() + 1), pending, now) }
    }

    @Test fun refusesBlankApiKey() {
        assertThrowsIOException { GeminiLiveAuth.createTokenRequest(" ", "instruction", now) }
    }

    private fun assertThrowsIOException(block: () -> Unit) {
        try {
            block()
            fail("Expected IOException")
        } catch (_: IOException) { }
    }
}
