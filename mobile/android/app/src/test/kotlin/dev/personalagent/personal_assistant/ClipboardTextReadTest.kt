package dev.personalagent.personal_assistant

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ClipboardTextReadTest {
    @Test
    fun `returns text only when Android identifies a plain text clipboard`() {
        assertEquals("sample", plainClipboardText(true, StringBuilder("sample")))
        assertNull(plainClipboardText(false, StringBuilder("not plain text")))
        assertNull(plainClipboardText(true, null))
    }
}
