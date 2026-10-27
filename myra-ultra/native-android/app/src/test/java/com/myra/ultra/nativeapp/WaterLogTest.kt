package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertNotNull
import org.junit.Test

class WaterLogTest {
    @Test fun validatesAmountsAndCalendarDates() {
        assertEquals(250, WaterLog.parseMilliliters(" 250 "))
        assertNull(WaterLog.parseMilliliters("0"))
        assertNull(WaterLog.parseMilliliters("4001"))
        assertNull(WaterLog.parseMilliliters("250.5"))
        assertNotNull(WaterLog.newEntry("2024-02-29", 250, "a"))
        assertNull(WaterLog.newEntry("2025-02-29", 250, "a"))
        assertNull(WaterLog.newEntry("2024-01-01", 0, "a"))
    }

    @Test fun roundTripsAndRejectsMalformedRows() {
        val entry = WaterEntry("entry|one", "2026-10-23", 330)
        assertEquals(entry, WaterLog.decode(WaterLog.encode(entry)))
        assertNull(WaterLog.decode("00|2026-02-30|330"))
        assertNull(WaterLog.decode("gg|2026-10-23|330"))
        assertNull(WaterLog.decode("00|2026-10-23|4001"))
    }

    @Test fun totalsAreScopedToExactDateAndUseLongArithmetic() {
        val entries = listOf(
            WaterEntry("a", "2026-10-23", 250),
            WaterEntry("b", "2026-10-23", 500),
            WaterEntry("c", "2026-10-22", 1000),
        )
        assertEquals(750L, WaterLog.totalForDate(entries, "2026-10-23"))
        assertEquals(1000L, WaterLog.totalForDate(entries, "2026-10-22"))
        assertEquals(0L, WaterLog.totalForDate(entries, "2026-10-21"))
    }
}
