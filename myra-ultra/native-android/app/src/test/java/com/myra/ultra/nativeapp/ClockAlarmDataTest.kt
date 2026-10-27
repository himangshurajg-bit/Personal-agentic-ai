package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ClockAlarmDataTest {
    @Test fun acceptsFirstAndLastValidClockValues() {
        assertEquals(ClockAlarmRequest(0, 0, "MYRA"), ClockAlarmData.parse("0", "0", " "))
        assertEquals(ClockAlarmRequest(23, 59, "Wake up"), ClockAlarmData.parse(" 23 ", "59", " Wake up "))
    }

    @Test fun rejectsOutOfRangeOrMalformedClockValues() {
        listOf(
            "" to "0", "24" to "0", "-1" to "0", "+1" to "0", "1.0" to "0", "100" to "0",
            "1" to "60", "1" to "-1", "1" to "+2", "1" to "1:00", "1" to "００"
        ).forEach { (hour, minute) -> assertNull("$hour:$minute", ClockAlarmData.parse(hour, minute, "MYRA")) }
    }

    @Test fun rejectsUnboundedOrControlCharacterLabels() {
        assertNull(ClockAlarmData.parse("7", "5", "x".repeat(ClockAlarmData.MAX_LABEL_LENGTH + 1)))
        assertNull(ClockAlarmData.parse("7", "5", "wake\nup"))
        assertEquals("x".repeat(ClockAlarmData.MAX_LABEL_LENGTH), ClockAlarmData.parse("7", "5", "x".repeat(ClockAlarmData.MAX_LABEL_LENGTH))?.label)
    }
}
