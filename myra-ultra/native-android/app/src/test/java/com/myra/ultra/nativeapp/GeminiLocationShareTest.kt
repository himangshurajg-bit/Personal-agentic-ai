package com.myra.ultra.nativeapp

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GeminiLocationShareTest {
    @Test fun exactCurrentLocationRequestsAreEligible() {
        listOf(
            "Where am I?",
            "Please show me where I am.",
            "What is my current location?",
            "What's my location",
            "Tell me my current location!",
            "Get my location",
            "Can you find my current location?",
            "Share my location",
        ).forEach { assertTrue("Expected explicit request: $it", GeminiLocationSharePolicy.hasExplicitIntent(it)) }
    }

    @Test fun vagueNegatedAndFutureRequestsDoNotTriggerLocationAccess() {
        listOf(
            "Where is the nearest cafe?",
            "What does location mean?",
            "Maybe get my location",
            "Don't get my current location",
            "Do not share my location",
            "Never tell me where I am",
            "Get my location tomorrow",
            "Share my location later",
            "Get my location if I ask",
            "",
        ).forEach { assertFalse("Unexpected location intent: $it", GeminiLocationSharePolicy.hasExplicitIntent(it)) }
    }

    @Test fun toolDeclarationAndArgumentsAreNarrowAndNoArgument() {
        val declaration = GeminiSafeTools.declaration().getJSONArray("functionDeclarations")
            .let { items -> (0 until items.length()).map { items.getJSONObject(it) }.single { it.getString("name") == GeminiLocationSharePolicy.TOOL } }
        assertTrue(declaration.getString("description").contains("coarse-location permission"))
        assertTrue(declaration.getString("description").contains("separate confirmation"))
        assertTrue(declaration.getString("description").contains("Google Gemini"))
        assertEquals(0, declaration.getJSONObject("parameters").getJSONObject("properties").length())
        assertEquals(GeminiLocationSharePolicy.TOOL, GeminiSafeTools.validate(GeminiLocationSharePolicy.TOOL, JSONObject()))
        listOf(JSONObject().put("latitude", 27.47), JSONObject().put("extra", true)).forEach { args ->
            try {
                GeminiSafeTools.validate(GeminiLocationSharePolicy.TOOL, args)
                throw AssertionError("Unexpected location arguments accepted")
            } catch (_: java.io.IOException) { }
        }
    }

    @Test fun coordinatesAreRoundedBeforeDisplayAndTransfer() {
        val fix = MyraLocationFix.create(27.472834, 94.912763, 17f, 1L)!!
        assertEquals("27.473, 94.913", GeminiLocationSharePolicy.roundedCoordinates(fix))
        val negative = MyraLocationFix.create(-27.472834, -94.912763, null, 1L)!!
        assertEquals("-27.473, -94.913", GeminiLocationSharePolicy.roundedCoordinates(negative))
    }
}
