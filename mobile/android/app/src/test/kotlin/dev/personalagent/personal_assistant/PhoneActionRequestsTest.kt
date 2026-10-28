package dev.personalagent.personal_assistant

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PhoneActionRequestsTest {
    @Test
    fun `WhatsApp draft requires one full international number and nonblank message`() {
        val valid = WhatsAppDraftPolicy.parse(" +14155550123 ", "  Hello there  ")
        assertEquals(WhatsAppDraftRequest("+14155550123", "  Hello there  "), valid)
        assertNull(WhatsAppDraftPolicy.parse("4155550123", "Hello"))
        assertNull(WhatsAppDraftPolicy.parse("+0123456789", "Hello"))
        assertNull(WhatsAppDraftPolicy.parse("+14155550123", "  "))
        assertNull(WhatsAppDraftPolicy.parse("+14155550123", "x".repeat(1_601)))
    }

    @Test
    fun `WhatsApp link encodes the exact message and cannot send it`() {
        val request = requireNotNull(
            WhatsAppDraftPolicy.parse("+14155550123", "Hi there\nplease review & reply"),
        )
        val link = WhatsAppDraftPolicy.link(request)
        assertTrue(link.startsWith("https://wa.me/14155550123?text="))
        assertTrue(link.endsWith("Hi%20there%0Aplease%20review%20%26%20reply"))
        assertTrue(link.contains("https://wa.me/"))
    }

    @Test
    fun `torch chooses a flash camera and prefers the rear camera`() {
        assertEquals(
            "rear",
            chooseTorchCamera(
                listOf(
                    TorchCameraCandidate("front", hasFlash = true, isBackFacing = false),
                    TorchCameraCandidate("rear", hasFlash = true, isBackFacing = true),
                    TorchCameraCandidate("no-flash", hasFlash = false, isBackFacing = true),
                ),
            ),
        )
        assertNull(chooseTorchCamera(listOf(TorchCameraCandidate("front", false, false))))
    }
}
