package com.myra.ultra.nativeapp

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.nio.file.Files

class CameraPhotoDataTest {
    @Test fun suggestedNameIsSafeAndKeepsTimestampUnique() {
        assertEquals("MYRA-photo-1730000000000.jpg", CameraPhotoData.suggestedFileName(1_730_000_000_000L))
        assertEquals("MYRA-photo-0.jpg", CameraPhotoData.suggestedFileName(-1L))
    }

    @Test fun tempCaptureFileIsUniqueAndContainedInPrivateCacheSubdirectory() {
        val cache = Files.createTempDirectory("myra-camera-test").toFile()
        try {
            val first = CameraPhotoData.createTempCaptureFile(cache, 1234L)
            val second = CameraPhotoData.createTempCaptureFile(cache, 1234L)
            assertTrue(first.isFile)
            assertTrue(second.isFile)
            assertTrue(first != second)
            assertEquals(java.io.File(cache, CameraPhotoData.CAPTURE_DIRECTORY), first.parentFile)
            assertTrue(first.name.startsWith("MYRA-capture-1234-"))
            assertTrue(first.name.endsWith(".jpg"))
            first.delete()
            second.delete()
        } finally {
            cache.deleteRecursively()
        }
    }

    @Test fun authorityIsDerivedFromTheAppPackage() {
        assertEquals("com.example.myra.camera-files", CameraPhotoData.providerAuthority("com.example.myra"))
    }

    @Test fun copiesAllFullResolutionBytesAndReportsLength() {
        val bytes = ByteArray(64 * 1024) { (it % 251).toByte() }
        val output = ByteArrayOutputStream()
        assertEquals(bytes.size.toLong(), CameraPhotoData.copyCapture(ByteArrayInputStream(bytes), output))
        assertArrayEquals(bytes, output.toByteArray())
    }

    @Test fun emptyInputReportsNoPhotoBytes() {
        val output = ByteArrayOutputStream()
        assertEquals(0L, CameraPhotoData.copyCapture(ByteArrayInputStream(byteArrayOf()), output))
        assertEquals(0, output.size())
    }

}
