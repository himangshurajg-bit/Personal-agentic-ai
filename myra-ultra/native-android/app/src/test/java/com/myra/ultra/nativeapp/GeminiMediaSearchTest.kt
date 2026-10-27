package com.myra.ultra.nativeapp

import java.io.IOException
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GeminiMediaSearchTest {
    @Test fun validatesOnlyKnownServiceAndBoundedQueryWithExactArguments() {
        val youtubeArgs = JSONObject().put("service", "youtube").put("query", "Mitski & Café")
        val request = GeminiSafeTools.mediaSearchRequest(youtubeArgs)
        assertEquals("Mitski & Café", request.media.query)
        assertEquals("https://www.youtube.com/results?search_query=Mitski+%26+Caf%C3%A9", request.media.uri)
        assertEquals(GeminiSafeTools.SEARCH_MEDIA, GeminiSafeTools.validate(GeminiSafeTools.SEARCH_MEDIA, youtubeArgs))
        assertEquals("spotify:search:Radiohead%20In%20Rainbows", GeminiSafeTools.mediaSearchRequest(
            JSONObject().put("service", "spotify").put("query", "Radiohead In Rainbows")
        ).media.uri)
        listOf(
            JSONObject(),
            JSONObject().put("service", "youtube").put("query", "   "),
            JSONObject().put("service", "youtube").put("query", "x".repeat(121)),
            JSONObject().put("service", "youtube").put("query", "song\nartist"),
            JSONObject().put("service", "arbitrary").put("query", "song"),
            JSONObject().put("service", "youtube").put("query", "song").put("extra", true),
            JSONObject().put("service", 123).put("query", "song"),
        ).forEach { args -> expectRejected { GeminiSafeTools.validate(GeminiSafeTools.SEARCH_MEDIA, args) } }
    }

    @Test fun onlyDirectLatestRequestForExactServiceAndQueryPasses() {
        val youtube = GeminiSafeTools.mediaSearchRequest(JSONObject().put("service", "youtube").put("query", "Mitski"))
        assertTrue(GeminiSafeTools.hasExplicitMediaSearchIntent("Search YouTube for Mitski", youtube))
        assertTrue(GeminiSafeTools.hasExplicitMediaSearchIntent("Find Mitski on YouTube", youtube))
        assertFalse(GeminiSafeTools.hasExplicitMediaSearchIntent("What is Mitski's best song on YouTube?", youtube))
        assertFalse(GeminiSafeTools.hasExplicitMediaSearchIntent("Search Spotify for Mitski", youtube))
        assertFalse(GeminiSafeTools.hasExplicitMediaSearchIntent("Don't search YouTube for Mitski", youtube))
        assertFalse(GeminiSafeTools.hasExplicitMediaSearchIntent("Search YouTube for Mitski tomorrow", youtube))
        assertFalse(GeminiSafeTools.hasExplicitMediaSearchIntent("Search YouTube for another artist", youtube))
        val spotify = GeminiSafeTools.mediaSearchRequest(JSONObject().put("service", "spotify").put("query", "Radiohead"))
        assertTrue(GeminiSafeTools.hasExplicitMediaSearchIntent("Could you find Radiohead on Spotify?", spotify))
        assertFalse(GeminiSafeTools.hasExplicitMediaSearchIntent("Search YouTube for Radiohead", spotify))
    }

    @Test fun intentRebuildsOnlyValidatedSearchUri() {
        val request = GeminiSafeTools.mediaSearchRequest(JSONObject().put("service", "spotify").put("query", "Björk Vespertine"))
        val intent = GeminiSafeTools.mediaSearchIntent(request)
        assertEquals("android.intent.action.VIEW", intent.action)
        assertEquals("spotify:search:Bj%C3%B6rk%20Vespertine", intent.data)
        assertEquals(null, intent.targetPackage)

        val youtube = GeminiSafeTools.mediaSearchRequest(JSONObject().put("service", "youtube").put("query", "Mitski"))
        val youtubeIntent = GeminiSafeTools.mediaSearchIntent(youtube)
        assertEquals("https://www.youtube.com/results?search_query=Mitski", youtubeIntent.data)
        assertEquals("com.google.android.youtube", youtubeIntent.targetPackage)
    }

    private fun expectRejected(block: () -> Unit) {
        try {
            block()
            throw AssertionError("Expected invalid media search to be rejected")
        } catch (_: IOException) {
        }
    }
}
