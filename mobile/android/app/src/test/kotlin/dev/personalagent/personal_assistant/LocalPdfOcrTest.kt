package dev.personalagent.personal_assistant

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LocalPdfOcrTest {
    @Test
    fun pageCountIsBounded() {
        assertEquals(0, localPdfOcrPageLimit(-1))
        assertEquals(3, localPdfOcrPageLimit(3))
        assertEquals(MAX_LOCAL_PDF_OCR_PAGES, localPdfOcrPageLimit(100))
    }

    @Test
    fun rasterSizeDoesNotUpscaleAndCapsLongestSide() {
        assertEquals(800 to 1200, localPdfOcrBitmapSize(800, 1200))
        assertEquals(1024 to 2048, localPdfOcrBitmapSize(4096, 8192))
        assertNull(localPdfOcrBitmapSize(0, 100))
        assertNull(localPdfOcrBitmapSize(100, 100, 0))
    }

    @Test
    fun pageTextIsBoundedAcrossPages() {
        val first = appendBoundedPdfPage("", 1, "A".repeat(MAX_LOCAL_PDF_OCR_CHARS))
        assertEquals(MAX_LOCAL_PDF_OCR_CHARS, first.length)
        assertEquals(true, pdfPageTextWouldTruncate("", 1, "A".repeat(MAX_LOCAL_PDF_OCR_CHARS)))
        val second = appendBoundedPdfPage(first, 2, "later")
        assertEquals(MAX_LOCAL_PDF_OCR_CHARS, second.length)
    }

    @Test
    fun pageNumberAndContentAreKeptWhenTheyFit() {
        assertEquals("Page 2\nHello", appendBoundedPdfPage("", 2, "Hello"))
        assertEquals(false, pdfPageTextWouldTruncate("", 2, "Hello"))
        assertEquals("Page 1\nOne\n\nPage 2\nTwo", appendBoundedPdfPage("Page 1\nOne", 2, "Two"))
    }
}
