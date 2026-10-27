package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GeminiModelCatalogTest {
    @Test fun defaultsToCurrentStableModelAndUnknownPreferencesFailClosed() {
        assertEquals("gemini-3.8-flash", GeminiModelCatalog.resolveId(null))
        assertEquals(GeminiModelCatalog.DEFAULT_ID, GeminiModelCatalog.resolveId("unknown/model"))
        assertEquals(GeminiModelCatalog.DEFAULT_ID, GeminiModelCatalog.resolveId("gemini-2.5-flash-preview-09-2025"))
    }

    @Test fun onlyDocumentedStableTextModelsAreSelectable() {
        assertEquals(setOf("gemini-3.8-flash", "gemini-3.5-flash-lite", "gemini-2.5-flash"), GeminiModelCatalog.options.map { it.id }.toSet())
        assertEquals(GeminiModelCatalog.options.size, GeminiModelCatalog.options.map { it.id }.distinct().size)
        assertTrue(GeminiModelCatalog.option("gemini-2.5-flash").note.contains("limited"))
        assertFalse(GeminiModelCatalog.options.any { it.id.contains("preview") || it.id.contains("latest") })
    }

    @Test fun endpointUsesAllowlistedModelAndSupportedMethod() {
        assertEquals("https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:streamGenerateContent", GeminiModelCatalog.endpoint("gemini-3.8-flash", "streamGenerateContent"))
        assertEquals("https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent", GeminiModelCatalog.endpoint("gemini-3.5-flash-lite", "generateContent"))
        assertEquals("https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent", GeminiModelCatalog.endpoint("https://attacker.invalid", "generateContent"))
    }

    @Test(expected = IllegalArgumentException::class)
    fun endpointRejectsUnrecognizedMethod() {
        GeminiModelCatalog.endpoint(GeminiModelCatalog.DEFAULT_ID, "deleteModel")
    }
}
