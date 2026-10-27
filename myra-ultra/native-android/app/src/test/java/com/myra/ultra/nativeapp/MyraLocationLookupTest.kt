package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MyraLocationLookupTest {
    @Test fun acceptsValidCoordinatesAndFormatsIndependentlyOfDeviceLocale() {
        val fix = MyraLocationFix.create(12.345678, -45.678912, 18.5f, 1234L)!!
        assertEquals("12.34568, -45.67891", fix.coordinates())
        assertEquals("geo:12.345678,-45.678912?q=12.345678,-45.678912", fix.mapsUri())
        assertEquals(18.5f, fix.accuracyMeters!!, 0f)
        assertEquals(1234L, fix.capturedAtMillis)
    }

    @Test fun rejectsNonFiniteOrOutOfRangeCoordinates() {
        assertNull(MyraLocationFix.create(Double.NaN, 0.0, null, 0))
        assertNull(MyraLocationFix.create(91.0, 0.0, null, 0))
        assertNull(MyraLocationFix.create(0.0, -181.0, null, 0))
        assertNull(MyraLocationFix.create(0.0, Double.POSITIVE_INFINITY, null, 0))
    }

    @Test fun discardsInvalidAccuracyAndClampsNegativeTimestamp() {
        val fix = MyraLocationFix.create(-90.0, 180.0, Float.NaN, -5L)!!
        assertNull(fix.accuracyMeters)
        assertEquals(0L, fix.capturedAtMillis)
    }
}
