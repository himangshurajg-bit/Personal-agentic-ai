package com.myra.ultra.nativeapp

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GeminiNameChangeTest {
    @Test fun nameToolIsDeclaredAndAcceptsOneBoundedName() {
        val request = GeminiSafeTools.nameChangeRequest(JSONObject().put("name", "  Himangshu   Raj "))
        assertEquals("Himangshu Raj", request.name)
        assertEquals(GeminiSafeTools.SET_NAME, GeminiSafeTools.validate(
            GeminiSafeTools.SET_NAME, JSONObject().put("name", "Himangshu")))
        val declarations = GeminiSafeTools.declaration().getJSONArray("functionDeclarations")
        val declaration = (0 until declarations.length()).map { declarations.getJSONObject(it) }
            .single { it.getString("name") == GeminiSafeTools.SET_NAME }
        assertTrue(declaration.getString("description").contains("approval"))
        assertEquals("name", declaration.getJSONObject("parameters").getJSONArray("required").getString(0))
    }

    @Test fun nameToolRejectsMalformedControlAndOversizedNames() {
        listOf(
            JSONObject(),
            JSONObject().put("name", ""),
            JSONObject().put("name", "\u0000bad"),
            JSONObject().put("name", "x".repeat(UserNamePreference.MAX_LENGTH + 1)),
            JSONObject().put("name", 4),
            JSONObject().put("name", "Raj").put("extra", true),
        ).forEach { args ->
            try {
                GeminiSafeTools.validate(GeminiSafeTools.SET_NAME, args)
                throw AssertionError("Expected invalid name request to fail: $args")
            } catch (_: java.io.IOException) { }
        }
        assertNull(UserNamePreference.normalize("\u0007"))
    }

    @Test fun nameChangeRequiresExplicitLatestTurnNamingStatementAndExactName() {
        val request = GeminiSafeTools.nameChangeRequest(JSONObject().put("name", "Raj Gogoi"))
        assertTrue(GeminiSafeTools.hasExplicitNameChangeIntent("Please call me Raj Gogoi", request))
        assertTrue(GeminiSafeTools.hasExplicitNameChangeIntent("My name is Raj Gogoi", request))
        assertTrue(GeminiSafeTools.hasExplicitNameChangeIntent("Set my name to Raj Gogoi", request))
        assertTrue(GeminiSafeTools.hasExplicitNameChangeIntent("Remember my name as Raj Gogoi", request))
        assertFalse(GeminiSafeTools.hasExplicitNameChangeIntent("Don't call me Raj Gogoi", request))
        assertFalse(GeminiSafeTools.hasExplicitNameChangeIntent("Maybe call me Raj Gogoi", request))
        assertFalse(GeminiSafeTools.hasExplicitNameChangeIntent("Call me Raj", request))
        assertFalse(GeminiSafeTools.hasExplicitNameChangeIntent("Please use the name Raj Gogoi", request))
    }
}
