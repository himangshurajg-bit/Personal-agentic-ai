package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GeminiPdfRequestTest {
    private val validPdf = "%PDF-1.7\nbody".toByteArray(Charsets.US_ASCII)

    @Test fun acceptsBoundedPdfWithSignatureAndRejectsInvalidInputs() {
        assertNull(GeminiPdfRequest.validationError("application/pdf", validPdf))
        assertEquals("Choose a PDF document.", GeminiPdfRequest.validationError("text/plain", validPdf))
        assertEquals("The selected file does not have a valid PDF signature.", GeminiPdfRequest.validationError("application/pdf", "not a pdf".toByteArray()))
        assertEquals("The selected PDF is empty or could not be read.", GeminiPdfRequest.validationError("application/pdf", byteArrayOf()))
        assertEquals("Choose a PDF no larger than 4 MiB.", GeminiPdfRequest.validationError("application/pdf", ByteArray(GeminiPdfRequest.MAX_PDF_BYTES + 1).also { "%PDF-".toByteArray().copyInto(it) }))
        assertEquals("Choose a PDF document.", GeminiPdfRequest.validationError(null, validPdf))
    }

    @Test fun buildsInlinePdfRequestWithMimeTypeAndBase64() {
        val request = GeminiPdfRequest.buildJson(validPdf, "Summarize it")
        assertNotNull(request)
        assertTrue(request!!.contains("\"mimeType\":\"application/pdf\""))
        assertTrue(request.contains("\"data\":\"JVBERi0xLjcKYm9keQ==\""))
        assertTrue(request.contains("\"text\":\"Summarize it\""))
    }

    @Test fun safelyEscapesAndBoundsUserPrompt() {
        val request = GeminiPdfRequest.buildJson(validPdf, "  quote: \"yes\" slash: \\ line\nnext  ")!!
        assertTrue(request.contains("quote: \\\"yes\\\" slash: \\\\ line\\nnext"))
        val longPrompt = "x".repeat(700)
        val bounded = GeminiPdfRequest.buildJson(validPdf, longPrompt)!!
        assertTrue(bounded.contains("\"text\":\"${"x".repeat(600)}\""))
        assertFalse(bounded.contains("x".repeat(601)))
    }

    @Test fun rejectsRequestConstructionForInvalidPdf() {
        assertNull(GeminiPdfRequest.buildJson("bad".toByteArray()))
        assertNull(GeminiPdfRequest.buildJson(ByteArray(GeminiPdfRequest.MAX_PDF_BYTES + 1).also { "%PDF-".toByteArray().copyInto(it) }))
    }
}
