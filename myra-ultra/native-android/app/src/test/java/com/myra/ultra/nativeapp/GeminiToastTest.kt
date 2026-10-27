package com.myra.ultra.nativeapp

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class GeminiToastTest {
    @Test fun requestAcceptsBoundedPrintableExactTextOnly() {
        val request = GeminiToastPolicy.request(JSONObject().put("text", "Saved"))
        assertEquals("Saved", request.text)
        assertEquals("show_toast", GeminiSafeTools.validate(GeminiSafeTools.SHOW_TOAST, JSONObject().put("text", "Saved")))
    }

    @Test fun requestRejectsEmptyLongControlAndUnexpectedArguments() {
        listOf("", " \n", "x".repeat(121), "hello\u0001").forEach { value ->
            assertThrows(Exception::class.java) { GeminiToastPolicy.request(JSONObject().put("text", value)) }
        }
        assertThrows(Exception::class.java) { GeminiToastPolicy.request(JSONObject().put("text", "ok").put("extra", true)) }
    }

    @Test fun toolRequiresExplicitToastRequestAndExactTextInLatestTurn() {
        val request = GeminiToastPolicy.request(JSONObject().put("text", "Build complete"))
        assertTrue(GeminiToastPolicy.hasExplicitIntent("Show a toast saying Build complete", request))
        assertTrue(GeminiToastPolicy.hasExplicitIntent("Display toast: Build complete", request))
        assertFalse(GeminiToastPolicy.hasExplicitIntent("Show a toast saying Build done", request))
        assertFalse(GeminiToastPolicy.hasExplicitIntent("Show a notification saying Build complete", request))
        assertFalse(GeminiToastPolicy.hasExplicitIntent("Don't show a toast saying Build complete", request))
        assertFalse(GeminiToastPolicy.hasExplicitIntent("Build complete", request))
    }
}
