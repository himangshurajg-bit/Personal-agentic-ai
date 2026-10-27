package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class JournalDataTest {
    @Test fun entryRequiresTextAndStrictDateAndEnforcesLength() {
        assertEquals("A note", JournalData.create("  A note  ", "2024-02-29", "e1")?.text)
        assertNull(JournalData.create("  \n ", "2024-02-29", "e1"))
        assertNull(JournalData.create("note", "2023-02-29", "e1"))
        assertNull(JournalData.create("x".repeat(JournalData.MAX_TEXT_LENGTH + 1), "2024-01-01", "e1"))
        assertFalse(JournalData.isValidDate("2024-1-01"))
        assertTrue(JournalData.isValidDate("2024-02-29"))
    }

    @Test fun entryCodecPreservesUnicodeDelimitersAndRejectsCorruption() {
        val entry = JournalData.create("Line one | \nनमस्ते 📚", "2025-04-03", "entry|1")!!
        assertEquals(entry, JournalData.decode(JournalData.encode(entry)))
        assertNull(JournalData.decode("bad"))
        assertNull(JournalData.decode("entry|2025-02-30|6e6f7465"))
        assertNull(JournalData.decode("entry|2025-04-03|zz"))
    }

    @Test fun entriesSortNewestDateFirst() {
        val a = JournalData.create("older", "2025-01-01", "a")!!
        val b = JournalData.create("newer", "2025-01-03", "b")!!
        val c = JournalData.create("same day", "2025-01-03", "c")!!
        assertEquals(listOf(c, b, a), JournalData.newestFirst(listOf(a, b, c)))
    }
}
