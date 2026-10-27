package dev.personalagent.personal_assistant

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalAudioQueueTest {
    private fun entry(index: Int, mime: String = "audio/mpeg") =
        LocalAudioQueueEntry("content://media/$index", "Track $index", mime)

    @Test
    fun addsUniqueAudioAndSkipsUnsupportedEntries() {
        val update = LocalAudioQueue.add(
            listOf(entry(1)),
            listOf(entry(1), entry(2), entry(3, "video/mp4"), entry(4, " AUDIO/OGG ")),
        )

        assertEquals(listOf("content://media/1", "content://media/2", "content://media/4"), update.entries.map { it.uriKey })
        assertEquals(2, update.addedCount)
        assertEquals(2, update.ignoredCount)
        assertEquals("audio/ogg", update.entries.last().mimeType)
    }

    @Test
    fun enforcesBoundAndTrimsStoredText() {
        val tooLongTitle = "x".repeat(LocalAudioQueue.MAX_TITLE_CHARS + 10)
        val update = LocalAudioQueue.add(
            emptyList(),
            (0 until LocalAudioQueue.MAX_ENTRIES + 2).map { index ->
                if (index == 0) entry(index).copy(title = tooLongTitle) else entry(index)
            },
        )

        assertEquals(LocalAudioQueue.MAX_ENTRIES, update.entries.size)
        assertEquals(LocalAudioQueue.MAX_ENTRIES, update.addedCount)
        assertEquals(2, update.ignoredCount)
        assertEquals(LocalAudioQueue.MAX_TITLE_CHARS, update.entries.first().title.length)
    }

    @Test
    fun returnsOnlyInRangeAdjacentIndices() {
        assertEquals(1, LocalAudioQueue.nextIndex(0, 3))
        assertEquals(2, LocalAudioQueue.nextIndex(1, 3))
        assertNull(LocalAudioQueue.nextIndex(2, 3))
        assertEquals(1, LocalAudioQueue.previousIndex(2, 3))
        assertNull(LocalAudioQueue.previousIndex(0, 3))
        assertNull(LocalAudioQueue.nextIndex(-1, 3))
        assertNull(LocalAudioQueue.previousIndex(0, 0))
    }

    @Test
    fun clampsSeekPositionAndPlaybackControlsFollowState() {
        assertEquals(0L, LocalAudioQueue.clampPosition(-10, 100))
        assertEquals(100L, LocalAudioQueue.clampPosition(500, 100))
        assertEquals(0L, LocalAudioQueue.clampPosition(500, -1))
        assertTrue(LocalAudioPlaybackState.PAUSED.canStartOrResume())
        assertTrue(LocalAudioPlaybackState.PLAYING.canPause())
        assertFalse(LocalAudioPlaybackState.READY.canPause())
        assertFalse(LocalAudioPlaybackState.EMPTY.canStop())
    }
}
