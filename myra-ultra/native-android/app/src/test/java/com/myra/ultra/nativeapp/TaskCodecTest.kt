package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TaskCodecTest {
    @Test fun roundTripsUnicodeAndDelimiters() {
        val task = MyraTask("123", "Check MYRA | Android ✓", true)
        assertEquals(task, decodeTask(encodeTask(task)))
    }

    @Test fun rejectsMalformedRecords() {
        assertNull(decodeTask("missing-fields"))
        assertNull(decodeTask("id|2|dGVzdA=="))
        assertNull(decodeTask("id|0|abz0"))
        assertNull(decodeTask("id|0|f"))
        assertNull(decodeTask("id|0|ff"))
    }
}
