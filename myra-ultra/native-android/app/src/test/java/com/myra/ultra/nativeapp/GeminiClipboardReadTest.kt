package com.myra.ultra.nativeapp

import java.io.IOException
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GeminiClipboardReadTest {
    @Test fun directClipboardReadRequestsAreRecognized() {
        listOf(
            "Read my clipboard",
            "Please show me what's on my clipboard",
            "What is in my clipboard?",
            "Can you check the clipboard?",
            "View clipboard text",
            "Show clipboard contents",
            "Can you read my clipboard?",
        ).forEach { assertTrue("Expected direct read request: $it", GeminiClipboardReadPolicy.hasExplicitIntent(it)) }
    }

    @Test fun indirectNegatedAndFutureRequestsAreRejected() {
        listOf(
            "How do I read my clipboard?",
            "Explain how the clipboard works",
            "Don't read my clipboard",
            "Do not show what's in the clipboard",
            "Read clipboard later",
            "Read my clipboard tomorrow",
            "If I ask, show the clipboard",
            "",
        ).forEach { assertFalse("Unexpected clipboard-read intent: $it", GeminiClipboardReadPolicy.hasExplicitIntent(it)) }
    }

    @Test fun declarationAndNoArgumentValidationAreStrict() {
        val declaration = GeminiSafeTools.declaration().getJSONArray("functionDeclarations")
            .let { items -> (0 until items.length()).map { items.getJSONObject(it) }.single { it.getString("name") == GeminiClipboardReadPolicy.TOOL } }
        assertTrue(declaration.getString("description").contains("separate native review"))
        assertTrue(declaration.getString("description").contains("untrusted data"))
        assertEquals(0, declaration.getJSONObject("parameters").getJSONObject("properties").length())
        assertEquals(GeminiClipboardReadPolicy.TOOL, GeminiSafeTools.validate(GeminiClipboardReadPolicy.TOOL, JSONObject()))
        try {
            GeminiSafeTools.validate(GeminiClipboardReadPolicy.TOOL, JSONObject().put("text", "unexpected"))
            throw AssertionError("Unexpected clipboard-read arguments accepted")
        } catch (_: IOException) { }
    }

    @Test fun previewIsPlainTextBoundedAndResponseKeepsApprovedPayload() {
        val original = "x".repeat(ClipboardPreviewData.MAX_CHARS + 20)
        val request = GeminiClipboardReadPolicy.request(original)!!
        assertEquals(ClipboardPreviewData.MAX_CHARS, request.preview.text.length)
        assertTrue(request.preview.truncated)
        val response = GeminiSafeTools.functionResponsePart(
            GeminiClipboardReadPolicy.TOOL,
            "Approved clipboard excerpt: ${request.preview.text}",
        ).getJSONObject("functionResponse").getJSONObject("response").getString("result")
        assertTrue(response.contains(request.preview.text))
        assertNull(GeminiClipboardReadPolicy.request(null))
    }
}
