package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.Assert.assertThrows

class ScreenShareProtocolTest {
    @Test fun acceptsOnlyTheOneUseInvitationShape() {
        val invitation = ScreenShareProtocol.parseInvitation(
            "{\"pairing_id\":\"0123456789abcdef0123456789abcdef\",\"pairing_code\":\"AbCdEf0123456789_-AbCdEf0123456789\"}",
        )
        assertEquals("0123456789abcdef0123456789abcdef", invitation.pairingId)
        assertEquals("AbCdEf0123456789_-AbCdEf0123456789", invitation.pairingCode)
        assertThrows(IllegalArgumentException::class.java) {
            ScreenShareProtocol.parseInvitation("{\"pairing_id\":\"0123456789abcdef0123456789abcdef\",\"pairing_code\":\"AbCdEf0123456789_-AbCdEf0123456789\",\"sender_token\":\"secret\"}")
        }
    }

    @Test fun rejectsInsecureOrCredentialBearingServiceAddresses() {
        assertThrows(IllegalArgumentException::class.java) { ScreenShareProtocol.normalizeServiceUrl("http://example.test") }
        assertThrows(IllegalArgumentException::class.java) { ScreenShareProtocol.normalizeServiceUrl("https://user:pass@example.test") }
        assertThrows(IllegalArgumentException::class.java) { ScreenShareProtocol.normalizeServiceUrl("https://example.test/?token=secret") }
    }

    @Test fun captureSizeIsDownsampledAndNeverUpscaled() {
        val large = ScreenShareProtocol.captureSize(2400, 1080)
        assertEquals(1280, large.width)
        assertEquals(576, large.height)
        assertEquals(ScreenShareFrameSize(640, 1280), ScreenShareProtocol.captureSize(700, 1400))
        assertEquals(ScreenShareFrameSize(700, 700), ScreenShareProtocol.captureSize(700, 700))
    }

    @Test fun streamMessageRequiresExplicitConsentAndBoundedCapture() {
        val start = ScreenShareProtocol.startMessage(1280, 720)
        assertEquals("start", start.getString("type"))
        assertTrue(start.getBoolean("media_projection_consent"))
        assertTrue(start.getBoolean("foreground_service"))
        assertEquals(3, start.getInt("fps"))
        assertThrows(IllegalArgumentException::class.java) { ScreenShareProtocol.startMessage(4096, 4096) }
        assertFalse(ScreenShareProtocol.isValidSessionId("../frame"))
    }

    @Test fun streamIsSecureAndSessionScoped() {
        val url = ScreenShareProtocol.streamUrl(
            "https://receiver.example",
            "0123456789abcdef0123456789abcdef",
        )
        // OkHttp requires HTTPS here and transparently upgrades newWebSocket calls to WSS.
        assertEquals("https", url.scheme)
        assertEquals("/screen-share/sessions/0123456789abcdef0123456789abcdef/stream", url.encodedPath)
    }
}
