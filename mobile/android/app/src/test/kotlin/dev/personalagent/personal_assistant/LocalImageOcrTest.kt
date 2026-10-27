package dev.personalagent.personal_assistant

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalImageOcrTest {
    @Test fun acceptsOnlySupportedImageFormats() {
        assertTrue(supportsLocalOcrMime("image/jpeg"))
        assertTrue(supportsLocalOcrMime("image/png"))
        assertTrue(supportsLocalOcrMime("image/webp"))
        assertFalse(supportsLocalOcrMime("application/pdf"))
        assertFalse(supportsLocalOcrMime("image/svg+xml"))
    }

    @Test fun boundsReturnedText() {
        assertEquals(MAX_LOCAL_OCR_CHARS, boundedLocalOcrText("x".repeat(MAX_LOCAL_OCR_CHARS + 50)).length)
        assertEquals("short", boundedLocalOcrText("short"))
    }

    @Test fun sampleSizeBoundsVeryLargeImagesWithoutUpscaling() {
        assertEquals(1, localOcrSampleSize(1600, 900))
        assertEquals(2, localOcrSampleSize(4096, 3000))
        assertEquals(8, localOcrSampleSize(16000, 12000))
        assertEquals(1, localOcrSampleSize(0, 900))
    }
}
