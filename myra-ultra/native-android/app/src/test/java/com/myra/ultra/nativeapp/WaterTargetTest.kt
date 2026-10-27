package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class WaterTargetTest {
    @Test fun acceptsOnlyWholeUserSelectedTargetsWithinBounds() {
        assertEquals(250, WaterTarget.parseMilliliters(" 250 "))
        assertEquals(20_000, WaterTarget.parseMilliliters("20000"))
        assertNull(WaterTarget.parseMilliliters(""))
        assertNull(WaterTarget.parseMilliliters("249"))
        assertNull(WaterTarget.parseMilliliters("20001"))
        assertNull(WaterTarget.parseMilliliters("1000.5"))
        assertNull(WaterTarget.parseMilliliters("1e3"))
    }

    @Test fun progressIsDateTotalRelativeAndCappedAtTheChosenGoal() {
        assertEquals(0.0f, WaterTarget.progress(0, 1000)!!, 0.0001f)
        assertEquals(0.5f, WaterTarget.progress(500, 1000)!!, 0.0001f)
        assertEquals(1.0f, WaterTarget.progress(1500, 1000)!!, 0.0001f)
        assertEquals(0.0f, WaterTarget.progress(-1, 1000)!!, 0.0001f)
        assertNull(WaterTarget.progress(500, 0))
    }

    @Test fun remainingAmountNeverGoesBelowZero() {
        assertEquals(500L, WaterTarget.remaining(500, 1000))
        assertEquals(0L, WaterTarget.remaining(1500, 1000))
        assertNull(WaterTarget.remaining(500, 0))
    }
}
