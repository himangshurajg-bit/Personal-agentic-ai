package dev.personalagent.personal_assistant

internal const val MAX_CAMERA_CAPTURE_BYTES = 2 * 1024 * 1024

/** Accept only bounded JPEG bytes returned by Android's user-launched camera app. */
internal fun isValidJpegCapture(bytes: ByteArray?): Boolean =
    bytes != null && bytes.size in 4..MAX_CAMERA_CAPTURE_BYTES &&
        bytes[0] == 0xff.toByte() && bytes[1] == 0xd8.toByte() &&
        bytes[bytes.lastIndex - 1] == 0xff.toByte() && bytes.last() == 0xd9.toByte()
