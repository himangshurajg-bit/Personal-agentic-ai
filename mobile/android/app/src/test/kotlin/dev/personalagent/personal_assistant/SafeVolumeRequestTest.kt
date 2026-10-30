package dev.personalagent.personal_assistant

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SafeVolumeRequestTest {
    @Test fun acceptsOnlyKnownStreamsAndIntegerPercentages() {
        SafeVolumeRequest.streams.forEach { assertTrue(SafeVolumeRequest.isValidStream(it)) }
        assertFalse(SafeVolumeRequest.isValidStream("voice"))
        assertEquals(0, SafeVolumeRequest.percent(0))
        assertEquals(100, SafeVolumeRequest.percent(100L))
        listOf(-1, 101, 1.5, "50", null).forEach { assertNull(SafeVolumeRequest.percent(it)) }
    }

    @Test fun mapsPercentAcrossNonzeroPlatformMinimumAndReportsActualPercent() {
        assertEquals(1, SafeVolumeRequest.levelForPercent(0, 1, 7))
        assertEquals(4, SafeVolumeRequest.levelForPercent(50, 1, 7))
        assertEquals(7, SafeVolumeRequest.levelForPercent(100, 1, 7))
        assertEquals(50, SafeVolumeRequest.percentForLevel(4, 1, 7))
    }

    @Test fun rejectsInvalidRangesAndHandlesFixedStreams() {
        assertNull(SafeVolumeRequest.levelForPercent(50, -1, 7))
        assertNull(SafeVolumeRequest.levelForPercent(50, 8, 7))
        assertEquals(0, SafeVolumeRequest.percentForLevel(3, 3, 3))
        assertNull(SafeVolumeRequest.percentForLevel(4, 3, 3))
    }
}
