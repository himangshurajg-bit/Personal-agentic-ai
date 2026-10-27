package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ShareTextTest {
    @Test fun trimsOnlyOuterWhitespaceAndRejectsBlankText() {
        assertEquals("hello\nworld", ShareTextData.normalize("  hello\nworld  "))
        assertNull(ShareTextData.normalize(" \n  \t "))
    }

    @Test fun boundsSharePayloadWithoutChangingInternalLineBreaks() {
        val source = "a".repeat(ShareTextData.MAX_LENGTH - 2) + "\nxyz"
        val shared = ShareTextData.normalize(source)!!
        assertEquals(ShareTextData.MAX_LENGTH, shared.length)
        assertEquals("\nx", shared.takeLast(2))
    }
}
