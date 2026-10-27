package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VolumeControlTest {
    @Test fun mapsEveryPrototypeStreamAndRejectsUnknownKeys() {
        assertEquals(listOf("music", "ring", "alarm", "notification", "system", "call"), MyraVolumeStream.values().map { it.key })
        MyraVolumeStream.values().forEach { assertTrue(MyraVolumeControl.isSupportedKey(it.key)) }
        assertFalse(MyraVolumeControl.isSupportedKey("voice"))
        assertFalse(MyraVolumeControl.isSupportedKey("MUSIC"))
    }

    @Test fun acceptsExplicitLevelsInsideDeviceReportedBounds() {
        assertTrue(MyraVolumeControl.isValidLevel(0, 0, 15))
        assertTrue(MyraVolumeControl.isValidLevel(7, 0, 15))
        assertTrue(MyraVolumeControl.isValidLevel(15, 0, 15))
        assertTrue(MyraVolumeControl.isValidLevel(2, 2, 8))
        assertTrue(MyraVolumeControl.isValidLevel(8, 2, 8))
    }

    @Test fun mapsReviewedPercentIntoAndroidReportedRange() {
        assertEquals(0, MyraVolumeControl.levelForPercent(0, 0, 15))
        assertEquals(8, MyraVolumeControl.levelForPercent(50, 0, 15))
        assertEquals(15, MyraVolumeControl.levelForPercent(100, 0, 15))
        assertEquals(5, MyraVolumeControl.levelForPercent(50, 2, 8))
        assertEquals(null, MyraVolumeControl.levelForPercent(-1, 0, 15))
        assertEquals(null, MyraVolumeControl.levelForPercent(101, 0, 15))
        assertEquals(null, MyraVolumeControl.levelForPercent(50, 8, 2))
    }

    @Test fun rejectsLevelsOutsideBoundsAndInvalidRanges() {
        assertFalse(MyraVolumeControl.isValidLevel(-1, 0, 15))
        assertFalse(MyraVolumeControl.isValidLevel(16, 0, 15))
        assertFalse(MyraVolumeControl.isValidLevel(1, 2, 8))
        assertFalse(MyraVolumeControl.isValidLevel(4, 5, 3))
        assertFalse(MyraVolumeControl.isValidLevel(0, -1, 3))
    }
}
