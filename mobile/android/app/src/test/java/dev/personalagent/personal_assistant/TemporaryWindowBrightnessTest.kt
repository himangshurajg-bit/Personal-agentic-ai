package dev.personalagent.personal_assistant

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TemporaryWindowBrightnessTest {
    @Test fun mapsInclusiveSourceRangeToWindowBrightness() {
        assertEquals(0f, temporaryWindowBrightness(0)!!, 0f)
        assertEquals(1f, temporaryWindowBrightness(255)!!, 0f)
        assertEquals(128f / 255f, temporaryWindowBrightness(128)!!, 0f)
    }

    @Test fun rejectsValuesOutsideSourceRange() {
        assertNull(temporaryWindowBrightness(-1))
        assertNull(temporaryWindowBrightness(256))
    }
}
