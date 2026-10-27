package com.myra.ultra.nativeapp

import java.io.IOException
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GeminiTimerPolicyTest {
    private fun args(seconds: Any = 300) = JSONObject().put("seconds", seconds)

    @Test fun acceptsOnlyBoundedIntegerDurationAndDeclaresReviewedTool() {
        assertEquals(ClockTimerRequest(300, "MYRA"), GeminiTimerPolicy.request(args()))
        assertEquals("5 minutes", GeminiTimerPolicy.request(args())?.displayDuration)
        assertEquals("1 hour", GeminiTimerPolicy.request(args(3600))?.displayDuration)
        assertEquals("90 seconds", GeminiTimerPolicy.request(args(90))?.displayDuration)
        assertEquals(GeminiSafeTools.SET_TIMER, GeminiSafeTools.validate(GeminiTimerPolicy.TOOL, args()))
        listOf(JSONObject(), args(0), args(-1), args(86_401), args("300"), args(60.0), args(300).put("label", "unreviewed"))
            .forEach { assertNull("$it", GeminiTimerPolicy.request(it)) }
        try {
            GeminiSafeTools.validate(GeminiTimerPolicy.TOOL, args(86_401))
            throw AssertionError("invalid timer duration should fail validation")
        } catch (_: IOException) { }
        val declaration = GeminiSafeTools.declaration().getJSONArray("functionDeclarations")
            .let { declarations -> (0 until declarations.length()).map { declarations.getJSONObject(it) } }
            .single { it.getString("name") == GeminiTimerPolicy.TOOL }
        assertTrue(declaration.getString("description").contains("native approval"))
        val props = declaration.getJSONObject("parameters").getJSONObject("properties")
        assertEquals("INTEGER", props.getJSONObject("seconds").getString("type"))
        assertEquals(1, props.getJSONObject("seconds").getInt("minimum"))
        assertEquals(86_400, props.getJSONObject("seconds").getInt("maximum"))
    }

    @Test fun acceptsOnlyOneExactDurationInDirectLatestTurnRequest() {
        assertTrue(GeminiTimerPolicy.hasExplicitIntent("Set a timer for 5 minutes", GeminiTimerPolicy.request(args(300))!!))
        assertTrue(GeminiTimerPolicy.hasExplicitIntent("Please start a timer for 90 seconds", GeminiTimerPolicy.request(args(90))!!))
        assertTrue(GeminiTimerPolicy.hasExplicitIntent("Create a timer for 2 hours", GeminiTimerPolicy.request(args(7_200))!!))
        assertFalse(GeminiTimerPolicy.hasExplicitIntent("Set a timer for 5 minutes", GeminiTimerPolicy.request(args(60))!!))
        assertFalse(GeminiTimerPolicy.hasExplicitIntent("Set a timer for 5 minutes or 10 minutes", GeminiTimerPolicy.request(args(300))!!))
        assertFalse(GeminiTimerPolicy.hasExplicitIntent("Don't set a timer for 5 minutes", GeminiTimerPolicy.request(args(300))!!))
        assertFalse(GeminiTimerPolicy.hasExplicitIntent("If I ask, set a timer for 5 minutes", GeminiTimerPolicy.request(args(300))!!))
        assertFalse(GeminiTimerPolicy.hasExplicitIntent("Set a timer for 5 minutes tomorrow", GeminiTimerPolicy.request(args(300))!!))
        assertFalse(GeminiTimerPolicy.hasExplicitIntent("Set a repeating timer for 5 minutes", GeminiTimerPolicy.request(args(300))!!))
        assertFalse(GeminiTimerPolicy.hasExplicitIntent("Set an alarm for 07:30 and a timer for 5 minutes", GeminiTimerPolicy.request(args(300))!!))
        assertFalse(GeminiTimerPolicy.hasExplicitIntent("What is a 5 minute timer?", GeminiTimerPolicy.request(args(300))!!))
        assertFalse(GeminiTimerPolicy.hasExplicitIntent("Set a timer for 25 hours", GeminiTimerPolicy.request(args(90_000)) ?: ClockTimerRequest(90_000, "MYRA")))
    }
}
