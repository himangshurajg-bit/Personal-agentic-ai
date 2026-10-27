package com.myra.ultra.nativeapp

import java.io.IOException
import java.util.Locale
import org.json.JSONObject

/** Privacy-reviewed transfer of one coarse location fix to Gemini for a direct current-location request. */
internal object GeminiLocationSharePolicy {
    const val TOOL = "get_current_location"

    fun validateArguments(args: JSONObject) {
        if (args.length() != 0) throw IOException("Gemini requested unexpected location arguments; no location was read or shared.")
    }

    fun hasExplicitIntent(userText: String): Boolean {
        val text = userText.trim().lowercase(Locale.ROOT)
        if (text.isEmpty() || Regex("\\b(?:don't|do not|never|not|without)\\b").containsMatchIn(text)) return false
        if (Regex("\\b(?:tomorrow|later|next week|when i|if i|in the future)\\b").containsMatchIn(text)) return false
        return Regex("^(?:please\\s+)?(?:where\\s+am\\s+i|show\\s+me\\s+where\\s+i\\s+am|what(?:'s|\\s+is)\\s+my\\s+(?:current\\s+)?location|tell\\s+me\\s+my\\s+(?:current\\s+)?location|(?:find|get|check|share|send)\\s+my\\s+(?:current\\s+)?location|can\\s+you\\s+(?:tell\\s+me\\s+)?(?:where\\s+am\\s+i|find\\s+my\\s+(?:current\\s+)?location|get\\s+my\\s+(?:current\\s+)?location))[?.!\\s]*$").containsMatchIn(text)
    }

    /** Round to roughly 100 m before displaying or transmitting; do not send a raw GPS fix. */
    fun roundedCoordinates(fix: MyraLocationFix): String =
        String.format(Locale.US, "%.3f, %.3f", fix.latitude, fix.longitude)
}
