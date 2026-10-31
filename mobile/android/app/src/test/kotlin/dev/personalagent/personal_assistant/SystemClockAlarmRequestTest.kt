package dev.personalagent.personal_assistant

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SystemClockAlarmRequestTest {
    @Test
    fun acceptsExactClockBounds() {
        assertEquals(SystemClockAlarmRequest(0, 0), SystemClockAlarmRequestParser.parse(0, 0))
        assertEquals(SystemClockAlarmRequest(23, 59), SystemClockAlarmRequestParser.parse(23, 59))
    }

    @Test
    fun rejectsOutOfRangeAndNonIntegerArguments() {
        listOf(-1, 24, "07", 7L, null).forEach {
            assertNull("unexpectedly accepted hour $it", SystemClockAlarmRequestParser.parse(it, 30))
        }
        listOf(-1, 60, "30", 30L, null).forEach {
            assertNull("unexpectedly accepted minute $it", SystemClockAlarmRequestParser.parse(7, it))
        }
    }
}
