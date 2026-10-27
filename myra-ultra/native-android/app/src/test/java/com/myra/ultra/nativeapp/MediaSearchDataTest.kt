package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MediaSearchDataTest {
    @Test fun trimsAndBuildsEncodedYouTubeSearchUrl() {
        val request = MediaSearchData.parse(MediaSearchService.YOUTUBE, "  Mitski & Café / live  ")
        assertEquals("Mitski & Café / live", request?.query)
        assertEquals("https://www.youtube.com/results?search_query=Mitski+%26+Caf%C3%A9+%2F+live", request?.uri)
    }

    @Test fun buildsSpotifySearchUriWithUriEncodedSpaces() {
        val request = MediaSearchData.parse(MediaSearchService.SPOTIFY, "  Radiohead: In Rainbows?  ")
        assertEquals("spotify:search:Radiohead%3A%20In%20Rainbows%3F", request?.uri)
    }

    @Test fun acceptsBoundaryAndSupplementaryUnicode() {
        assertEquals(MediaSearchData.MAX_QUERY_LENGTH, MediaSearchData.parse(MediaSearchService.YOUTUBE, "x".repeat(MediaSearchData.MAX_QUERY_LENGTH))?.query?.length)
        assertEquals("spotify:search:%F0%9F%8C%8D", MediaSearchData.parse(MediaSearchService.SPOTIFY, "🌍")?.uri)
    }

    @Test fun rejectsEmptyOversizedControlAndMalformedUnicodeQueries() {
        listOf("", " \t ", "x".repeat(MediaSearchData.MAX_QUERY_LENGTH + 1), "song\nartist", "song\u0000artist", "song\uD800", "song\uDC00").forEach {
            assertNull("${it.take(24)}", MediaSearchData.parse(MediaSearchService.SPOTIFY, it))
        }
    }
}
