package dev.personalagent.personal_assistant

import java.net.URLEncoder

internal data class MapSearchRequest(val destination: String, val uri: String)

/** A bounded, exact user-entered destination for a Maps search handoff. */
internal object MapSearchRequestParser {
    fun parse(raw: Any?): MapSearchRequest? {
        val destination = (raw as? String)?.trim() ?: return null
        if (destination.isEmpty() || destination.length > 120 ||
            destination.any { it.isISOControl() }
        ) return null
        val encoded = try { URLEncoder.encode(destination, "UTF-8").replace("+", "%20") }
        catch (_: Exception) { return null }
        return MapSearchRequest(destination, "geo:0,0?q=$encoded")
    }
}
