package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DownloadDataTest {
    @Test fun acceptsHttpAndHttpsButRejectsInvalidOrCredentialBearingUrls() {
        assertEquals("report.pdf", DownloadData.validate("https://example.com/files/report.pdf?download=1")?.fileName)
        assertEquals("a.txt", DownloadData.validate("http://example.com/a.txt")?.fileName)
        listOf("", "not a URL", "file:///etc/passwd", "ftp://example.com/a", "https:///missing-host", "https://user:pass@example.com/a", "https://example.com\n/a", "https://example.com/" + "a".repeat(DownloadData.MAX_URL_LENGTH)).forEach {
            assertNull("should reject $it", DownloadData.validate(it))
        }
    }

    @Test fun filenameIsDerivedFromUrlPathAndSanitized() {
        assertEquals("hello world.txt", DownloadData.validate("https://example.com/hello%20world.txt")?.fileName)
        assertEquals("myra-download", DownloadData.validate("https://example.com/")?.fileName)
        val target = DownloadData.validate("https://example.com/%2F..%2Fbad%3Aname.txt")
        assertNotNull(target)
        assertFalse(target!!.fileName.contains('/'))
        assertFalse(target.fileName.contains('\\'))
        assertTrue(target.fileName.length <= DownloadData.MAX_FILE_NAME_LENGTH)
        val longName = DownloadData.validate("https://example.com/" + "x".repeat(180))
        assertEquals(DownloadData.MAX_FILE_NAME_LENGTH, longName?.fileName?.length)
        assertEquals("myra-download", DownloadData.validate("https://example.com/..")?.fileName)
    }

    @Test fun downloadReferencesRoundTripAndMalformedRowsAreIgnored() {
        val ref = DownloadRef(1234L, "notes|v2.csv")
        assertEquals(ref, DownloadRef.decode(ref.encode()))
        assertNull(DownloadRef.decode("broken"))
        assertNull(DownloadRef.decode("not-a-number|file.txt"))
        assertNull(DownloadRef.decode("12|"))
    }

    @Test fun progressAndStatusHandleUnknownLengthsAndBoundaries() {
        assertEquals(0, downloadProgress(0, 100))
        assertEquals(50, downloadProgress(50, 100))
        assertEquals(100, downloadProgress(120, 100))
        assertEquals(100, downloadProgress(Long.MAX_VALUE, Long.MAX_VALUE))
        assertNull(downloadProgress(20, -1))
        assertNull(downloadProgress(-1, 100))
        assertEquals("Downloaded", downloadStatusLabel(LocalDownloadStatus.COMPLETE, 100))
        assertEquals("Downloading · 25%", downloadStatusLabel(LocalDownloadStatus.RUNNING, 25))
    }
}
