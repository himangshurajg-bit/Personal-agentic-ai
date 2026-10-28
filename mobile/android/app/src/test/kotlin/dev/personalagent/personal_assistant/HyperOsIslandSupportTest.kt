package dev.personalagent.personal_assistant

import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HyperOsIslandSupportTest {
    private fun payload(
        buildOptIn: Boolean = true,
        manufacturer: String = "Xiaomi",
        brand: String = "Xiaomi",
        islandSystemFeature: Boolean = true,
        protocolVersion: Int = 3,
        status: String = "Preparing your request",
    ) = buildHyperOsIslandPayload(
        buildOptIn,
        manufacturer,
        brand,
        islandSystemFeature,
        protocolVersion,
        status,
    )

    @Test
    fun payloadIsStrictlyGatedByOptInXiaomiIslandAndOs3Protocol() {
        assertNotNull(payload())
        assertNull(payload(buildOptIn = false))
        assertNull(payload(manufacturer = "Google", brand = "Pixel"))
        assertNull(payload(islandSystemFeature = false))
        assertNull(payload(protocolVersion = 2)) // OS2 requires a different template path.
        assertNull(payload(protocolVersion = 0))
    }

    @Test
    fun payloadUsesDocumentedParamV2AndTemplate2WithoutInventingProgress() {
        val json = payload() ?: error("expected gated payload")
        assertTrue(json.startsWith("{\"param_v2\":{"))
        assertTrue(json.contains("\"protocol\":1"))
        assertTrue(json.contains("\"business\":\"personal_ai_task\""))
        assertTrue(json.contains("\"imageTextInfoLeft\":{"))
        assertTrue(json.contains("\"smallIslandArea\":{"))
        assertTrue(json.contains("\"baseInfo\":{"))
        assertTrue(json.contains("\"timeout\":5"))
        assertTrue(json.contains("\"islandTimeout\":300"))
        assertFalse(json.contains("\"progress\""))
    }

    @Test
    fun onlyKnownGenericStatusTextCanReachTheVendorPayload() {
        assertTrue(payload(status = "Waiting for the selected AI")!!.contains("\"title\":\"Waiting\""))
        assertTrue(payload(status = "Running the on-device model")!!.contains("\"title\":\"On-device\""))
        assertTrue(payload(status = "Receiving the reply")!!.contains("\"title\":\"Replying\""))
        assertNull(payload(status = "private user prompt"))
        assertNull(payload(status = "my custom task title"))
    }

    @Test
    fun hardwareBrandFallbackAcceptsRedmiAndPocoOnlyWithOs3Capability() {
        assertTrue(canUseHyperOsIsland(true, "Xiaomi", "Redmi", true, 3))
        assertTrue(canUseHyperOsIsland(true, "Xiaomi", "POCO", true, 3))
        assertFalse(canUseHyperOsIsland(false, "Xiaomi", "Redmi", true, 3))
    }
}
