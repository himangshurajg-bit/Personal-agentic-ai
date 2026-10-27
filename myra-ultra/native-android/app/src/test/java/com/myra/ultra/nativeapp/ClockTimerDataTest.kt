package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ClockTimerDataTest {
    @Test fun acceptsBoundaryDurationsAndUsesDefaultLabel() {
        assertEquals(ClockTimerRequest(1, "MYRA"), ClockTimerData.parse("1", " "))
        assertEquals(ClockTimerRequest(86_400, "Study"), ClockTimerData.parse(" 86400 ", " Study "))
    }

    @Test fun rejectsMalformedOrOutOfRangeDurations() {
        listOf("", "0", "-1", "+1", "1.5", "1e2", "86401", "1000000", "１２").forEach {
            assertNull("$it", ClockTimerData.parse(it, "MYRA"))
        }
    }

    @Test fun rejectsOverlongOrControlCharacterLabels() {
        assertNull(ClockTimerData.parse("60", "x".repeat(ClockTimerData.MAX_LABEL_LENGTH + 1)))
        assertNull(ClockTimerData.parse("60", "study\ntimer"))
        assertEquals("x".repeat(ClockTimerData.MAX_LABEL_LENGTH), ClockTimerData.parse("60", "x".repeat(ClockTimerData.MAX_LABEL_LENGTH))?.label)
    }
}
