package com.myra.ultra.nativeapp

import org.junit.Assert.*
import org.junit.Test

class LocalActivityFeedTest {
    @Test fun recordsNewestFirstAndRoundTripsUnicode() {
        val first = LocalActivityFeed.record(emptyList(), "Task added", "A task was added locally.", 10L, "event-1")!!
        val second = LocalActivityFeed.record(first, "Workflow step completed", "A step was completed ✓", 20L, "event-2")!!
        assertEquals(listOf("event-2", "event-1"), second.map { it.id })
        assertEquals(second, LocalActivityFeed.decode(LocalActivityFeed.encode(second)))
    }

    @Test fun rejectsInvalidEventsAndTruncatesOldHistory() {
        assertNull(LocalActivityFeed.record(emptyList(), " ", "detail", 1L, "id"))
        assertNull(LocalActivityFeed.record(emptyList(), "Label", "detail", -1L, "id"))
        assertNull(LocalActivityFeed.record(emptyList(), "x".repeat(49), "detail", 1L, "id"))
        assertNull(LocalActivityFeed.record(emptyList(), "Label", "x".repeat(121), 1L, "id"))
        val events = (1..LocalActivityFeed.MAX_EVENTS + 1).fold(emptyList<LocalActivityEvent>()) { current, n ->
            LocalActivityFeed.record(current, "Task updated", "A local task changed.", n.toLong(), "id-$n")!!
        }
        assertEquals(LocalActivityFeed.MAX_EVENTS, events.size)
        assertEquals("id-${LocalActivityFeed.MAX_EVENTS + 1}", events.first().id)
        assertFalse(events.any { it.id == "id-1" })
    }

    @Test fun ignoresMalformedRowsAndDuplicateIds() {
        val good = LocalActivityFeed.record(emptyList(), "Task added", "A task was added locally.", 5L, "same")!!
        assertNull(LocalActivityFeed.record(good, "Task deleted", "A task was removed.", 6L, "same"))
        val serialized = LocalActivityFeed.encode(good) + "\nnot-an-event\n@@|bad|@@|@@"
        assertEquals(good, LocalActivityFeed.decode(serialized))
    }
}
