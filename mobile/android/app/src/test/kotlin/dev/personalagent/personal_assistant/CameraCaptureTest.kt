package dev.personalagent.personal_assistant

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CameraCaptureTest {
    @Test fun acceptsOnlyBoundedJpegPayloads() {
        assertTrue(isValidJpegCapture(byteArrayOf(0xff.toByte(), 0xd8.toByte(), 1, 0xff.toByte(), 0xd9.toByte())))
        assertFalse(isValidJpegCapture(null))
        assertFalse(isValidJpegCapture(byteArrayOf(1, 2, 3, 4)))
        assertFalse(isValidJpegCapture(byteArrayOf(0xff.toByte(), 0xd8.toByte(), 1, 0xff.toByte(), 0xd8.toByte())))
        assertFalse(isValidJpegCapture(ByteArray(MAX_CAMERA_CAPTURE_BYTES + 1)))
    }
}
