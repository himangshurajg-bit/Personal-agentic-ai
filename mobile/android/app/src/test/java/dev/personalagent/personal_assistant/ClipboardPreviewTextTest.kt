package dev.personalagent.personal_assistant

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ClipboardPreviewTextTest {
    @Test fun preservesShortPlainTextWithoutTruncation() {
        assertEquals(
            ClipboardPreviewText("hello\nworld", false),
            boundedClipboardPreview("hello\nworld"),
        )
    }

    @Test fun truncatesAtFourThousandCharacters() {
        val preview = boundedClipboardPreview("x".repeat(MAX_CLIPBOARD_PREVIEW_CHARS + 2))!!
        assertEquals(MAX_CLIPBOARD_PREVIEW_CHARS, preview.text.length)
        assertTrue(preview.truncated)
    }

    @Test fun exactLimitIsNotMarkedTruncated() {
        val preview = boundedClipboardPreview("x".repeat(MAX_CLIPBOARD_PREVIEW_CHARS))!!
        assertEquals(MAX_CLIPBOARD_PREVIEW_CHARS, preview.text.length)
        assertFalse(preview.truncated)
    }

    @Test fun doesNotTurnMissingOrEmptyClipboardIntoText() {
        assertNull(boundedClipboardPreview(null))
        assertNull(boundedClipboardPreview(""))
    }
}
