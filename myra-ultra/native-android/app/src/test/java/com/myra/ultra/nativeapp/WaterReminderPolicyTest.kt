package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

class WaterReminderPolicyTest {
    private val utc = TimeZone.getTimeZone("UTC")

    @Test fun parsesOnlyValidTwentyFourHourTimes() {
        assertEquals(0, WaterReminderPolicy.parseMinutesSinceMidnight("00:00"))
        assertEquals(9 * 60 + 5, WaterReminderPolicy.parseMinutesSinceMidnight(" 09:05 "))
        assertEquals(23 * 60 + 59, WaterReminderPolicy.parseMinutesSinceMidnight("23:59"))
        listOf("", "9:05", "24:00", "12:60", "12:3x", "1e2:00").forEach {
            assertNull("$it must be rejected", WaterReminderPolicy.parseMinutesSinceMidnight(it))
        }
    }

    @Test fun nextOccurrenceUsesLocalTimeAndRollsPastTimesToTomorrow() {
        val parser = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US).apply { isLenient = false; timeZone = utc }
        val morning = parser.parse("2026-10-26 08:00")!!.time
        assertEquals("2026-10-26 09:15", parser.format(java.util.Date(WaterReminderPolicy.nextOccurrence(morning, 9 * 60 + 15, utc)!!)))
        val exact = parser.parse("2026-10-26 09:15")!!.time
        assertEquals("2026-10-27 09:15", parser.format(java.util.Date(WaterReminderPolicy.nextOccurrence(exact, 9 * 60 + 15, utc)!!)))
        assertNull(WaterReminderPolicy.nextOccurrence(morning, 1440, utc))
    }

    @Test fun targetRemindersAreOptInAndStopAtTheChosenGoal() {
        assertFalse(WaterReminderPolicy.shouldNotify(false, 1000, 0))
        assertFalse(WaterReminderPolicy.shouldNotify(true, 0, 0))
        assertFalse(WaterReminderPolicy.shouldNotify(true, 1000, 1000))
        assertFalse(WaterReminderPolicy.shouldNotify(true, 1000, 1200))
        assertTrue(WaterReminderPolicy.shouldNotify(true, 1000, 999))
        assertTrue(WaterReminderPolicy.shouldNotify(true, 1000, -1))
    }
}
