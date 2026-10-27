package com.myra.ultra.nativeapp

import java.io.IOException
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GeminiAlarmPolicyTest {
    private fun args(hour: Any = 7, minute: Any = 30) = JSONObject().put("hour", hour).put("minute", minute)

    @Test fun acceptsOnlyBoundedIntegerHourAndMinuteAndDeclaresReviewedTool() {
        val request = GeminiAlarmPolicy.request(args())
        assertEquals(ClockAlarmRequest(7, 30, "MYRA"), request)
        assertEquals(GeminiSafeTools.SET_ALARM, GeminiSafeTools.validate(GeminiAlarmPolicy.TOOL, args()))
        listOf(
            JSONObject(), args(24, 0), args(-1, 0), args(7, 60), args("7", 30),
            args(7.5, 30), args(7, 30).put("label", "unreviewed"),
        ).forEach { assertNull("$it", GeminiAlarmPolicy.request(it)) }
        try {
            GeminiSafeTools.validate(GeminiAlarmPolicy.TOOL, args(24, 0))
            throw AssertionError("invalid alarm time should fail validation")
        } catch (_: IOException) { }
        val declaration = GeminiSafeTools.declaration().getJSONArray("functionDeclarations")
            .let { declarations -> (0 until declarations.length()).map { declarations.getJSONObject(it) } }
            .single { it.getString("name") == GeminiAlarmPolicy.TOOL }
        assertTrue(declaration.getString("description").contains("native approval"))
        val props = declaration.getJSONObject("parameters").getJSONObject("properties")
        assertEquals("INTEGER", props.getJSONObject("hour").getString("type"))
        assertEquals(0, props.getJSONObject("hour").getInt("minimum"))
        assertEquals(23, props.getJSONObject("hour").getInt("maximum"))
        assertEquals(59, props.getJSONObject("minute").getInt("maximum"))
    }

    @Test fun onlyExactOneOff24HourTimeInDirectLatestRequestIsAccepted() {
        val request = GeminiAlarmPolicy.request(args(7, 30))!!
        assertTrue(GeminiAlarmPolicy.hasExplicitIntent("Please set an alarm for 07:30", request))
        assertTrue(GeminiAlarmPolicy.hasExplicitIntent("Create an alarm at 07:30, please", request))
        assertFalse(GeminiAlarmPolicy.hasExplicitIntent("Set an alarm for 08:30", request))
        assertFalse(GeminiAlarmPolicy.hasExplicitIntent("Set an alarm for 7:30", request))
        assertFalse(GeminiAlarmPolicy.hasExplicitIntent("Set an alarm for 07:30 or 08:30", request))
        assertFalse(GeminiAlarmPolicy.hasExplicitIntent("Don't set an alarm for 07:30", request))
        assertFalse(GeminiAlarmPolicy.hasExplicitIntent("If I ask, set an alarm for 07:30", request))
        assertFalse(GeminiAlarmPolicy.hasExplicitIntent("Set an alarm for 07:30 tomorrow", request))
        assertFalse(GeminiAlarmPolicy.hasExplicitIntent("Set a daily alarm for 07:30", request))
        assertFalse(GeminiAlarmPolicy.hasExplicitIntent("What time is my alarm? 07:30", request))
        assertFalse(GeminiAlarmPolicy.hasExplicitIntent("Set an alarm for 07:30 and a timer at 08:30", request))
        assertNotNull(ClockAlarmData.parse("7", "30", ""))
    }
}
