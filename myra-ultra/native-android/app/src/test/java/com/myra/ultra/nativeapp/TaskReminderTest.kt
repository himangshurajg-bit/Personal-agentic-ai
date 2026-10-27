package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.TimeZone

class TaskReminderTest {
    private val utc = TimeZone.getTimeZone("UTC")

    @Test fun parsesStrictDateTimeAndDateOnly() {
        assertEquals(1_767_269_700_000L, parseTaskDueAt("2026-01-01", "12:15", utc))
        assertEquals(1_767_225_600_000L, parseTaskDueAt("2026-01-01", "", utc))
        assertNull(parseTaskDueAt("2026-02-30", "12:00", utc))
        assertNull(parseTaskDueAt("2026-1-01", "12:00", utc))
        assertNull(parseTaskDueAt("2026-01-01", "24:00", utc))
        assertNull(parseTaskDueAt("", "12:00", utc))
        assertNull(parseTaskDueAt("", "", utc))
    }

    @Test fun taskCodecReadsLegacyAndPersistsOptionalDateAndReminderFields() {
        val legacy = decodeTask("t1|0|5461736b")
        assertEquals(MyraTask("t1", "Task", false), legacy)
        val dated = MyraTask("t2", "Submit form", false, 1_767_269_700_000L, true, true)
        assertEquals(dated, decodeTask(encodeTask(dated)))
        val recurring = dated.copy(repeatEveryDays = 7)
        assertEquals(recurring, decodeTask(encodeTask(recurring)))
        val disabledReminder = taskWithReminderDisabled(recurring)
        assertEquals(dated.copy(reminderEnabled = false), disabledReminder)
        assertEquals(disabledReminder, decodeTask(encodeTask(disabledReminder)))
        assertEquals(dated, decodeTask("t2|0|5375626d697420666f726d|1767269700000|1|1"))
        assertNull(decodeTask("t2|0|5461736b|bad|0|0"))
        assertNull(decodeTask("t2|0|5461736b||0|1"))
        assertNull(decodeTask("t2|0|5461736b|1767225300000|1|0"))
        assertNull(decodeTask("t2|0|5461736b|1767225300000|1|1|2"))
        assertNull(decodeTask("t2|0|5461736b|1767225300000|0|1|1"))
    }

    @Test fun dailyAndWeeklyRecurrenceAdvancesByLocalCalendarDaysAndSkipsMissedOccurrences() {
        val zone = TimeZone.getTimeZone("America/New_York")
        val parser = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm", java.util.Locale.US).apply { isLenient = false; timeZone = zone }
        val first = parser.parse("2026-03-07 09:00")!!.time
        val next = nextRecurringDueAt(first, 1, first, zone)!!
        assertEquals("2026-03-08 09:00", parser.format(java.util.Date(next)))
        assertEquals(23L * 60 * 60 * 1000, next - first) // DST starts; preserve 09:00 local.
        val afterMissedDays = parser.parse("2026-03-11 10:00")!!.time
        val following = nextRecurringDueAt(first, 1, afterMissedDays, zone)!!
        assertEquals("2026-03-12 09:00", parser.format(java.util.Date(following)))
        val weekly = nextRecurringDueAt(first, 7, first, zone)!!
        assertEquals("2026-03-14 09:00", parser.format(java.util.Date(weekly)))
        assertNull(nextRecurringDueAt(first, 2, first, zone))
    }

    @Test fun reminderRequiresEnabledFutureTimedOpenTask() {
        val now = 1_767_269_700_000L
        val eligible = MyraTask("t", "Task", false, now + 60_000, true, true)
        assertTrue(isTaskReminderEligible(eligible, now))
        assertFalse(isTaskReminderEligible(eligible.copy(done = true), now))
        assertFalse(isTaskReminderEligible(eligible.copy(reminderEnabled = false), now))
        assertFalse(isTaskReminderEligible(eligible.copy(dueAtMillis = now - 1), now))
        assertFalse(isTaskReminderEligible(eligible.copy(dueHasTime = false), now))
    }
}
