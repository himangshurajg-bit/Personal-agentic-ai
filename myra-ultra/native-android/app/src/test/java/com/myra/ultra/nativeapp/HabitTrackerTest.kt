package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HabitTrackerTest {
    @Test fun titleValidationTrimsAndBoundsInput() {
        assertEquals("Read", HabitTracker.normalizedTitle("  Read  "))
        assertNull(HabitTracker.create(" \n "))
        assertNull(HabitTracker.create("x".repeat(81)))
        assertNull(HabitTracker.create("bad\nname"))
    }

    @Test fun strictDateValidationRejectsImpossibleDates() {
        assertTrue(HabitTracker.isValidDate("2024-02-29"))
        assertFalse(HabitTracker.isValidDate("2023-02-29"))
        assertFalse(HabitTracker.isValidDate("2024-2-09"))
    }

    @Test fun checkInToggleIsIdempotentByDateAndRejectsInvalidDates() {
        val habit = HabitTracker.create("Walk", "h1")!!
        val checked = HabitTracker.toggle(habit, "2025-04-03")!!
        assertTrue("2025-04-03" in checked.completedDates)
        assertFalse("2025-04-03" in HabitTracker.toggle(checked, "2025-04-03")!!.completedDates)
        assertNull(HabitTracker.toggle(habit, "2025-02-30"))
    }

    @Test fun streakCountsConsecutiveDaysAndAllowsYesterdayStart() {
        val base = HabitTracker.create("Read", "r")!!
        val checked = base.copy(completedDates = setOf("2025-01-01", "2025-01-02", "2025-01-04"))
        assertEquals(1, HabitTracker.currentStreak(checked, "2025-01-04"))
        assertEquals(1, HabitTracker.currentStreak(checked, "2025-01-05"))
        assertEquals(0, HabitTracker.currentStreak(checked, "2025-01-07"))
        val yesterdayRun = base.copy(completedDates = setOf("2025-01-04", "2025-01-05"))
        assertEquals(2, HabitTracker.currentStreak(yesterdayRun, "2025-01-06"))
        val newYear = base.copy(completedDates = setOf("2024-12-31", "2025-01-01"))
        assertEquals(2, HabitTracker.currentStreak(newYear, "2025-01-01"))
    }

    @Test fun recentHistoryIsSevenLocalCalendarDaysOldestFirstAcrossMonthAndYear() {
        assertEquals(
            listOf("2024-12-29", "2024-12-30", "2024-12-31", "2025-01-01", "2025-01-02", "2025-01-03", "2025-01-04"),
            HabitTracker.recentDates("2025-01-04"),
        )
        assertEquals(listOf("2024-02-27", "2024-02-28", "2024-02-29"), HabitTracker.recentDates("2024-02-29", 3))
        assertTrue(HabitTracker.recentDates("2025-02-30").isEmpty())
        assertTrue(HabitTracker.recentDates("2025-01-04", 0).isEmpty())
        assertTrue(HabitTracker.recentDates("2025-01-04", 32).isEmpty())
    }

    @Test fun recentCompletionCountIncludesOnlyWindowThroughToday() {
        val habit = HabitTracker.create("Read", "r")!!.copy(
            completedDates = setOf("2025-01-01", "2025-01-03", "2025-01-04", "2025-01-05", "2024-12-28"),
        )
        assertEquals(3, HabitTracker.recentCompletionCount(habit, "2025-01-04"))
        assertEquals(2, HabitTracker.recentCompletionCount(habit, "2025-01-04", 2))
        assertEquals(0, HabitTracker.recentCompletionCount(habit, "bad"))
    }

    @Test fun recordRoundTripsUnicodeAndCheckInDates() {
        val habit = HabitTracker.create("Read 📚", "habit/1")!!.copy(
            completedDates = setOf("2025-01-02", "2025-01-01"),
        )
        assertEquals(habit, HabitTracker.decode(HabitTracker.encode(habit)))
        assertNull(HabitTracker.decode("bad"))
        assertNull(HabitTracker.decode("00|ff|2025-02-30"))
    }
}
