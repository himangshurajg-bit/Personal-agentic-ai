package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MapsDestinationDataTest {
    @Test fun trimsAndBuildsAnEncodedGeoSearchUri() {
        val request = MapsDestinationData.parse("  New York & 5th / Café  ")
        assertEquals("New York & 5th / Café", request?.place)
        assertEquals("geo:0,0?q=New+York+%26+5th+%2F+Caf%C3%A9", request?.uri)
    }

    @Test fun acceptsTheMaximumLengthAndUnicodeSupplementaryCharacters() {
        assertEquals(MapsDestinationData.MAX_LENGTH, MapsDestinationData.parse("x".repeat(MapsDestinationData.MAX_LENGTH))?.place?.length)
        assertEquals("geo:0,0?q=%F0%9F%8C%8D", MapsDestinationData.parse("🌍")?.uri)
    }

    @Test fun rejectsEmptyOversizedAndControlCharacterDestinations() {
        listOf("", " \t ", "x".repeat(MapsDestinationData.MAX_LENGTH + 1), "12 Main St\nSuite 4", "Park\u0000Gate").forEach {
            assertNull("${it.take(20)}", MapsDestinationData.parse(it))
        }
    }

    @Test fun rejectsMalformedSurrogateSequences() {
        assertNull(MapsDestinationData.parse("place\uD800"))
        assertNull(MapsDestinationData.parse("place\uDC00"))
    }
}
