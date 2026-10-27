package com.myra.ultra.nativeapp

import java.io.IOException
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GeminiShareTextTest {
    @Test fun acceptsBoundedPlainTextAndDeclaresOnlyExactTextArgument() {
        val exact = "A note to share\nsecond line"
        val args = JSONObject().put("text", exact)
        val request = GeminiShareTextPolicy.request(args)
        assertEquals(exact, request.text)
        assertEquals(GeminiShareTextPolicy.TOOL, GeminiSafeTools.validate(GeminiShareTextPolicy.TOOL, args))
        val intent = GeminiShareTextPolicy.intent(request)
        assertEquals("android.intent.action.SEND", intent.action)
        assertEquals("text/plain", intent.mimeType)
        assertEquals(exact, intent.text)
        val declarations = GeminiSafeTools.declaration().getJSONArray("functionDeclarations")
        val declaration = (0 until declarations.length())
            .map { declarations.getJSONObject(it) }
            .single { it.getString("name") == GeminiShareTextPolicy.TOOL }
        assertTrue(declaration.getString("description").contains("never chooses a destination or sends"))
        assertEquals("text", declaration.getJSONObject("parameters").getJSONArray("required").getString(0))
    }

    @Test fun rejectsMissingUnexpectedUnprintableAndOversizedTextInsteadOfTruncating() {
        listOf(
            JSONObject(),
            JSONObject().put("text", " \n "),
            JSONObject().put("text", "x".repeat(GeminiShareTextPolicy.MAX_LENGTH + 1)),
            JSONObject().put("text", "bad\u0000text"),
            JSONObject().put("text", "valid").put("extra", true),
            JSONObject().put("text", 42),
        ).forEach { args -> expectRejected { GeminiShareTextPolicy.request(args) } }
    }

    @Test fun requiresExplicitShareAndExactTextInLatestMessage() {
        val request = GeminiShareTextRequest("Hello there")
        assertTrue(GeminiShareTextPolicy.hasExplicitIntent("Please share this exact text: Hello there", request))
        assertTrue(GeminiShareTextPolicy.hasExplicitIntent("Forward: Hello there", request))
        assertFalse(GeminiShareTextPolicy.hasExplicitIntent("Could you send this? Hello there", request))
        assertFalse(GeminiShareTextPolicy.hasExplicitIntent("Don't share this: Hello there", request))
        assertTrue(GeminiShareTextPolicy.hasExplicitIntent("Please share this: Hello there!", request))
        assertFalse(GeminiShareTextPolicy.hasExplicitIntent("Please share a similar note", request))
        assertFalse(GeminiShareTextPolicy.hasExplicitIntent("Please share this later: Hello there", request))
    }

    private fun expectRejected(block: () -> Unit) {
        try { block(); throw AssertionError("Expected invalid share request to be rejected") }
        catch (error: IOException) { assertTrue(error.message!!.isNotBlank()) }
    }
}
