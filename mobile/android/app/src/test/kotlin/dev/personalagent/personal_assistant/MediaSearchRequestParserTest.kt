package dev.personalagent.personal_assistant

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MediaSearchRequestParserTest {
    @Test fun buildsSearchOnlyUrlsWithEncodedQueries() {
        assertEquals(
            MediaSearchRequest("youtube", "lofi study", "https://www.youtube.com/results?search_query=lofi%20study"),
            MediaSearchRequestParser.parse("youtube", " lofi study "),
        )
        assertEquals(
            "https://open.spotify.com/search/%E0%A4%95%E0%A4%BF%E0%A4%B6%E0%A5%8B%E0%A4%B0%20%E0%A4%95%E0%A5%81%E0%A4%AE%E0%A4%BE%E0%A4%B0",
            MediaSearchRequestParser.parse("spotify", "किशोर कुमार")?.uri,
        )
    }

    @Test fun rejectsUnknownServicesEmptyQueriesControlsAndOversizedInput() {
        listOf("", "apple_music").forEach { assertNull(MediaSearchRequestParser.parse(it, "song")) }
        listOf("", "  ", "x".repeat(121), "one\ntwo").forEach {
            assertNull(MediaSearchRequestParser.parse("youtube", it))
        }
    }

    @Test fun rejectsUnpairedSurrogates() {
        assertNull(MediaSearchRequestParser.parse("youtube", "bad\uD800"))
        assertNull(MediaSearchRequestParser.parse("youtube", "bad\uDC00"))
    }
}
