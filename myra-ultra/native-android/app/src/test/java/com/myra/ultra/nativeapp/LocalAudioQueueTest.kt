package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LocalAudioQueueTest {
    private fun item(key: String, mime: String = "audio/mpeg", title: String = key) = LocalAudioQueueEntry(key, title, mime)

    @Test fun appendsOnlySupportedUniquePickerEntriesInOrder() {
        val result = LocalAudioQueue.add(listOf(item("one")), listOf(item("two"), item("one"), item("image", "image/jpeg"), item("three")))
        assertEquals(listOf("one", "two", "three"), result.entries.map { it.uriKey })
        assertEquals(2, result.addedCount)
        assertEquals(2, result.ignoredCount)
    }

    @Test fun trimsReferencesAndBoundsTitles() {
        val title = "x".repeat(LocalAudioQueue.MAX_TITLE_CHARS + 10)
        val result = LocalAudioQueue.add(emptyList(), listOf(item(" uri ", title = title)))
        assertEquals("uri", result.entries.single().uriKey)
        assertEquals(LocalAudioQueue.MAX_TITLE_CHARS, result.entries.single().title.length)
    }

    @Test fun capsQueueAtTwentyFiveEntries() {
        val input = (0..LocalAudioQueue.MAX_ENTRIES).map { item("uri-$it") }
        val result = LocalAudioQueue.add(emptyList(), input)
        assertEquals(LocalAudioQueue.MAX_ENTRIES, result.entries.size)
        assertEquals(LocalAudioQueue.MAX_ENTRIES, result.addedCount)
        assertEquals(1, result.ignoredCount)
        assertEquals(true, result.isFull)
    }

    @Test fun navigationDoesNotWrapAndRejectsInvalidIndexes() {
        assertEquals(1, LocalAudioQueue.nextIndex(0, 2))
        assertNull(LocalAudioQueue.nextIndex(1, 2))
        assertNull(LocalAudioQueue.nextIndex(-1, 2))
        assertEquals(0, LocalAudioQueue.previousIndex(1, 2))
        assertNull(LocalAudioQueue.previousIndex(0, 2))
        assertNull(LocalAudioQueue.previousIndex(0, 0))
    }
}
