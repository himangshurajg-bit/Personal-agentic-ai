package com.myra.ultra.nativeapp

import java.net.URLEncoder
import java.nio.charset.StandardCharsets

internal enum class MediaSearchService(val label: String) {
    YOUTUBE("YouTube"), SPOTIFY("Spotify")
}

internal data class MediaSearchRequest(val service: MediaSearchService, val query: String, val uri: String)

/** Bounded user-entered media search; creates only a search URI, never a playback request. */
internal object MediaSearchData {
    const val MAX_QUERY_LENGTH = 120

    fun parse(service: MediaSearchService, rawQuery: String): MediaSearchRequest? {
        val query = rawQuery.trim()
        if (query.isEmpty() || query.length > MAX_QUERY_LENGTH || query.any(Char::isISOControl)) return null
        var index = 0
        while (index < query.length) {
            val char = query[index]
            when {
                Character.isHighSurrogate(char) -> {
                    if (index + 1 >= query.length || !Character.isLowSurrogate(query[index + 1])) return null
                    index += 2
                }
                Character.isLowSurrogate(char) -> return null
                else -> index++
            }
        }
        val encoded = URLEncoder.encode(query, StandardCharsets.UTF_8.name())
        val uri = when (service) {
            MediaSearchService.YOUTUBE -> "https://www.youtube.com/results?search_query=$encoded"
            // Spotify's custom scheme expects URI percent-encoding; encode spaces as %20 rather than form '+' .
            MediaSearchService.SPOTIFY -> "spotify:search:${encoded.replace("+", "%20")}"
        }
        return MediaSearchRequest(service, query, uri)
    }
}
