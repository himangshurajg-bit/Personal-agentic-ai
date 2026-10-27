package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ClipboardPreviewTest {
    @Test fun noTextReturnsNoPreviewAndExistingTextIsPreserved() {
        assertNull(ClipboardPreviewData.fromText(null))
        assertNull(ClipboardPreviewData.fromText(""))
        assertEquals(ClipboardPreview("  private text\n", false), ClipboardPreviewData.fromText("  private text\n"))
    }

    @Test fun previewIsBoundedAndMarksTruncation() {
        val preview = ClipboardPreviewData.fromText("x".repeat(ClipboardPreviewData.MAX_CHARS + 3))!!
        assertEquals(ClipboardPreviewData.MAX_CHARS, preview.text.length)
        assertTrue(preview.truncated)
    }

    @Test fun truncationDoesNotSplitSurrogatePairs() {
        val source = "a".repeat(ClipboardPreviewData.MAX_CHARS - 1) + "😀tail"
        val preview = ClipboardPreviewData.fromText(source)!!
        assertEquals(ClipboardPreviewData.MAX_CHARS - 1, preview.text.length)
        assertFalse(preview.text.last().isHighSurrogate())
        assertTrue(preview.truncated)
    }
}
