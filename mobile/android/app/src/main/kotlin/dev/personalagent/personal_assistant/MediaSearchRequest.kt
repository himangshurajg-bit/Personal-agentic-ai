package dev.personalagent.personal_assistant

import java.net.URLEncoder
import java.nio.charset.StandardCharsets

internal data class MediaSearchRequest(val service: String, val query: String, val uri: String)

/** Validates a single explicit search and builds a search-only Android handoff. */
internal object MediaSearchRequestParser {
    const val MAX_QUERY_LENGTH = 120

    fun parse(serviceValue: Any?, rawQuery: Any?): MediaSearchRequest? {
        val service = serviceValue as? String ?: return null
        if (service !in setOf("youtube", "spotify")) return null
        val query = (rawQuery as? String)?.trim() ?: return null
        if (query.isEmpty() || query.length > MAX_QUERY_LENGTH || query.any(Char::isISOControl)) return null
        var index = 0
        while (index < query.length) {
            val char = query[index]
            if (char.isHighSurrogate()) {
                if (index + 1 >= query.length || !query[index + 1].isLowSurrogate()) return null
                index += 2
            } else {
                if (char.isLowSurrogate()) return null
                index++
            }
        }
        val encoded = URLEncoder.encode(query, StandardCharsets.UTF_8.name()).replace("+", "%20")
        val uri = when (service) {
            "youtube" -> "https://www.youtube.com/results?search_query=$encoded"
            else -> "https://open.spotify.com/search/$encoded"
        }
        return MediaSearchRequest(service, query, uri)
    }
}
