package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MyraWindowBrightnessTest {
    @Test fun normalizationClampsToAndroidWindowBrightnessLevelRange() {
        assertEquals(0, MyraWindowBrightness.normalizeLevel(-10))
        assertEquals(0, MyraWindowBrightness.normalizeLevel(0))
        assertEquals(128, MyraWindowBrightness.normalizeLevel(128))
        assertEquals(255, MyraWindowBrightness.normalizeLevel(255))
        assertEquals(255, MyraWindowBrightness.normalizeLevel(900))
    }

    @Test fun rangeCheckAcceptsOnlyPrototypeLevels() {
        assertTrue(MyraWindowBrightness.isValidLevel(0))
        assertTrue(MyraWindowBrightness.isValidLevel(255))
        assertFalse(MyraWindowBrightness.isValidLevel(-1))
        assertFalse(MyraWindowBrightness.isValidLevel(256))
    }

    @Test fun mapsLevelToWindowFractionWithoutChangingSystemBrightness() {
        assertEquals(0f, MyraWindowBrightness.toWindowBrightness(0), 0f)
        assertEquals(128f / 255f, MyraWindowBrightness.toWindowBrightness(128), 0f)
        assertEquals(1f, MyraWindowBrightness.toWindowBrightness(255), 0f)
        assertEquals(0f, MyraWindowBrightness.toWindowBrightness(-1), 0f)
        assertEquals(1f, MyraWindowBrightness.toWindowBrightness(256), 0f)
    }
}
