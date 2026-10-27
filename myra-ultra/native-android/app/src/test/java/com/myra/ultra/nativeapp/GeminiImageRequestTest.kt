package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GeminiImageRequestTest {
    @Test fun acceptsMatchingSmallImageAndBuildsInlineRequest() {
        val jpeg = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte(), 0x01)
        assertNull(GeminiImageRequest.validationError("image/jpeg", jpeg))
        val body = GeminiImageRequest.buildJson("image/jpeg", jpeg)!!
        assertTrue(body.contains("\"mimeType\":\"image/jpeg\""))
        assertTrue(body.contains("\"data\":\"/9j/AQ==\""))
        assertTrue(body.contains("Describe this image clearly"))
        assertFalse(body.contains("apiKey"))
    }

    @Test fun rejectsMissingUnsupportedOversizeAndMismatchedImages() {
        assertEquals("Choose a JPEG, PNG, or WebP image.", GeminiImageRequest.validationError("image/gif", byteArrayOf(1)))
        assertEquals("The selected image is empty or could not be read.", GeminiImageRequest.validationError("image/jpeg", byteArrayOf()))
        assertEquals("The file content does not match its image type.", GeminiImageRequest.validationError("image/png", byteArrayOf(1, 2, 3)))
        val tooLarge = ByteArray(GeminiImageRequest.MAX_IMAGE_BYTES + 1)
        tooLarge[0] = 0xFF.toByte(); tooLarge[1] = 0xD8.toByte(); tooLarge[2] = 0xFF.toByte()
        assertEquals("Choose an image no larger than 4 MiB.", GeminiImageRequest.validationError("image/jpeg", tooLarge))
        assertNull(GeminiImageRequest.buildJson("image/gif", byteArrayOf(1)))
    }
}
