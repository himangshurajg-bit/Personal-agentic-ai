package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Test

class PomodoroTimerTest {
    @Test fun countsDownUsingDeadlineAndRoundsUpPartialSecond() {
        assertEquals(60, PomodoroTimer.remainingSeconds(160_000L, 0, 100_000L))
        assertEquals(2, PomodoroTimer.remainingSeconds(101_001L, 0, 100_000L))
        assertEquals(0, PomodoroTimer.remainingSeconds(99_000L, 0, 100_000L))
    }

    @Test fun pausedTimeAndStartDeadlineAreStable() {
        assertEquals(125, PomodoroTimer.remainingSeconds(null, 125, 1_000L))
        assertEquals(66_000L, PomodoroTimer.deadlineAfter(1_000L, 65))
    }

    @Test fun formatsMinutesAndClampsNegativeValues() {
        assertEquals("25:00", PomodoroTimer.format(FocusPhase.FOCUS.durationSeconds))
        assertEquals("00:05", PomodoroTimer.format(5))
        assertEquals("00:00", PomodoroTimer.format(-9))
    }
}
