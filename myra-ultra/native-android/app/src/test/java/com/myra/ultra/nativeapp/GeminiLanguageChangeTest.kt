package com.myra.ultra.nativeapp

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GeminiLanguageChangeTest {
    @Test fun languageToolAcceptsOnlyOneExactSupportedLanguage() {
        val request = GeminiSafeTools.languageChangeRequest(JSONObject().put("language", "Spanish"))
        assertEquals("es", request.option.code)
        assertEquals(GeminiSafeTools.SET_LANGUAGE, GeminiSafeTools.validate(
            GeminiSafeTools.SET_LANGUAGE, JSONObject().put("language", "es")))
        val declarations = GeminiSafeTools.declaration().getJSONArray("functionDeclarations")
        val declaration = (0 until declarations.length()).map { declarations.getJSONObject(it) }
            .single { it.getString("name") == GeminiSafeTools.SET_LANGUAGE }
        assertTrue(declaration.getString("description").contains("approves"))
        assertEquals("language", declaration.getJSONObject("parameters").getJSONArray("required").getString(0))
    }

    @Test fun rejectsMalformedUnsupportedAndExtraLanguageArguments() {
        listOf(
            JSONObject(),
            JSONObject().put("language", "Klingon"),
            JSONObject().put("language", 5),
            JSONObject().put("language", "Spanish").put("extra", true),
            JSONObject().put("language", ""),
        ).forEach { args ->
            try {
                GeminiSafeTools.validate(GeminiSafeTools.SET_LANGUAGE, args)
                throw AssertionError("Expected invalid language request to fail: $args")
            } catch (_: java.io.IOException) { }
        }
    }

    @Test fun persistentLanguageRequiresDirectLatestTurnRequestNamingExactChoice() {
        val spanish = GeminiSafeTools.languageChangeRequest(JSONObject().put("language", "Spanish"))
        assertTrue(GeminiSafeTools.hasExplicitLanguageChangeIntent("Please change my reply language to Spanish", spanish))
        assertTrue(GeminiSafeTools.hasExplicitLanguageChangeIntent("From now on, reply in Spanish", spanish))
        assertTrue(GeminiSafeTools.hasExplicitLanguageChangeIntent("Please set my language to Spanish", spanish))
        assertTrue(GeminiSafeTools.hasExplicitLanguageChangeIntent("Switch language to ES", spanish))
        val assamese = GeminiSafeTools.languageChangeRequest(JSONObject().put("language", "as"))
        assertTrue(GeminiSafeTools.hasExplicitLanguageChangeIntent("Please change the reply language to Assamese (অসমীয়া)", assamese))
        assertFalse(GeminiSafeTools.hasExplicitLanguageChangeIntent("Translate this sentence to Spanish", spanish))
        assertFalse(GeminiSafeTools.hasExplicitLanguageChangeIntent("Can you speak Spanish?", spanish))
        assertFalse(GeminiSafeTools.hasExplicitLanguageChangeIntent("Please speak Spanish for this answer", spanish))
        assertFalse(GeminiSafeTools.hasExplicitLanguageChangeIntent("Maybe change my language to Spanish", spanish))
        assertFalse(GeminiSafeTools.hasExplicitLanguageChangeIntent("Don't change my language to Spanish", spanish))
        assertFalse(GeminiSafeTools.hasExplicitLanguageChangeIntent("Please change my language to French", spanish))
        assertFalse(GeminiSafeTools.hasExplicitLanguageChangeIntent("Please change my language to Spanish instead of French", spanish))
        assertFalse(GeminiSafeTools.hasExplicitLanguageChangeIntent("Please change my language to this", spanish))
    }
}
