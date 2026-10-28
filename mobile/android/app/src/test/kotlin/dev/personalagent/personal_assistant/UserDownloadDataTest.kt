package dev.personalagent.personal_assistant

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class UserDownloadDataTest {
    @Test fun acceptsOnlyCredentialFreeHttpUrls() {
        assertEquals("report.pdf", UserDownloadData.validate(" https://example.com/files/report.pdf?x=1 ")?.fileName)
        listOf(null, "", "file:///tmp/a", "https:/missing", "https://user:pass@example.com/a", "javascript:alert(1)")
            .forEach { assertNull(it, UserDownloadData.validate(it)) }
    }

    @Test fun stripsUnsafeFilenameCharactersAndBoundsInput() {
        assertEquals("_secret_.txt", UserDownloadData.validate("https://example.com/%3Csecret%3E.txt")?.fileName)
        assertEquals("download", UserDownloadData.validate("https://example.com/")?.fileName)
        assertNull(UserDownloadData.validate("https://example.com/${"a".repeat(2049)}"))
    }

    @Test fun filenamesArePathSafeAndCollisionsGetDistinctNames() {
        assertEquals("_secret_file.pdf", UserDownloadData.safeFileName("../secret/file.pdf", "download"))
        assertEquals("report (2).pdf", UserDownloadData.uniqueFileName("report.pdf", setOf("report.pdf")))
        assertEquals("report (3).pdf", UserDownloadData.uniqueFileName("report.pdf", setOf("report.pdf", "report (2).pdf")))
    }

    @Test fun persistedReferencesAndProgressAreBounded() {
        val ref = UserDownloadRef(42, "file.zip")
        assertEquals(ref, UserDownloadRef.decode(ref.encode()))
        assertNull(UserDownloadRef.decode("0|file.zip"))
        assertNull(UserDownloadRef.decode("bad"))
        assertEquals(50, UserDownloadData.progress(50, 100))
        assertEquals(100, UserDownloadData.progress(150, 100))
        assertNull(UserDownloadData.progress(-1, 100))
        assertNull(UserDownloadData.progress(1, 0))
    }
}
