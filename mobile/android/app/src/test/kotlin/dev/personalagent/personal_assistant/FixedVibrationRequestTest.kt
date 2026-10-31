package dev.personalagent.personal_assistant

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class FixedVibrationRequestTest {
    @Test fun onlyNoArgumentRequestGetsOneFixedShortPulse() {
        assertEquals(80L, FixedVibrationRequestParser.parse(null)?.durationMillis)
        assertEquals(80L, FixedVibrationRequestParser.parse(emptyMap<String, Any>())?.durationMillis)
    }

    @Test fun callerCannotSetDurationOrPattern() {
        assertNull(FixedVibrationRequestParser.parse(mapOf("duration" to 500L)))
        assertNull(FixedVibrationRequestParser.parse(mapOf("repeat" to true)))
        assertNull(FixedVibrationRequestParser.parse("80"))
    }
}
