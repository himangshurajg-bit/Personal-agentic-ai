package dev.personalagent.personal_assistant

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SystemClockTimerRequestTest {
    @Test fun acceptsInclusiveDurationBoundsAndOptionalLabel() {
        assertEquals(SystemClockTimerRequest(1, ""), SystemClockTimerRequestParser.parse(1, ""))
        assertEquals(SystemClockTimerRequest(86_400, "tea"), SystemClockTimerRequestParser.parse(86_400, " tea "))
    }

    @Test fun rejectsOutOfRangeAndNonWholeSecondValues() {
        listOf(0, 86_401, "", "1.5", "-1", "1000000", 1.5, null).forEach {
            assertNull("unexpectedly accepted duration $it", SystemClockTimerRequestParser.parse(it, "label"))
        }
    }

    @Test fun enforcesOptionalLabelLimitAndRejectsControlCharacters() {
        assertEquals(40, SystemClockTimerRequestParser.parse(60, "x".repeat(40))?.label?.length)
        assertNull(SystemClockTimerRequestParser.parse(60, "x".repeat(41)))
        assertNull(SystemClockTimerRequestParser.parse(60, "tea\nbreak"))
        assertNull(SystemClockTimerRequestParser.parse(60, null))
    }
}
