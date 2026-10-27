package com.myra.ultra.nativeapp

import java.io.File
import java.io.InputStream
import java.io.OutputStream

/** Metadata and bounded filesystem helpers for app-owned camera capture temp files. */
internal object CameraPhotoData {
    const val CAPTURE_DIRECTORY = "camera-captures"

    fun suggestedFileName(capturedAtMillis: Long): String {
        val safeMillis = capturedAtMillis.coerceAtLeast(0L)
        return "MYRA-photo-$safeMillis.jpg"
    }

    fun providerAuthority(packageName: String): String = "$packageName.camera-files"

    fun createTempCaptureFile(cacheDir: File, capturedAtMillis: Long): File {
        val directory = File(cacheDir, CAPTURE_DIRECTORY)
        if (!directory.exists() && !directory.mkdirs()) {
            throw IllegalStateException("Could not create the private camera capture directory.")
        }
        if (!directory.isDirectory) throw IllegalStateException("Private camera capture path is not a directory.")
        val safeMillis = capturedAtMillis.coerceAtLeast(0L)
        return File.createTempFile("MYRA-capture-$safeMillis-", ".jpg", directory)
    }

    /** Copies the captured full-resolution bytes and returns their count; empty output is not a photo. */
    fun copyCapture(input: InputStream, output: OutputStream): Long {
        var total = 0L
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        while (true) {
            val read = input.read(buffer)
            if (read < 0) break
            if (read == 0) continue
            output.write(buffer, 0, read)
            total += read
        }
        output.flush()
        return total
    }
}
