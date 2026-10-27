package com.myra.ultra.nativeapp

import java.net.URLEncoder
import java.nio.charset.StandardCharsets

/** Bounded user-entered destination for an explicit Android Maps/search handoff. */
internal data class MapsDestinationRequest(val place: String, val uri: String)

internal object MapsDestinationData {
    const val MAX_LENGTH = 200

    /** Returns null for empty, oversized, control-containing, or malformed Unicode input. */
    fun parse(rawPlace: String): MapsDestinationRequest? {
        val place = rawPlace.trim()
        if (place.isEmpty() || place.length > MAX_LENGTH || place.any(Char::isISOControl)) return null
        var index = 0
        while (index < place.length) {
            val char = place[index]
            when {
                Character.isHighSurrogate(char) -> {
                    if (index + 1 >= place.length || !Character.isLowSurrogate(place[index + 1])) return null
                    index += 2
                }
                Character.isLowSurrogate(char) -> return null
                else -> index++
            }
        }
        val encoded = URLEncoder.encode(place, StandardCharsets.UTF_8.name())
        return MapsDestinationRequest(place, "geo:0,0?q=$encoded")
    }
}
