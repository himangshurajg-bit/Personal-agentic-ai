package com.myra.ultra.nativeapp

import java.io.IOException
import java.util.Locale
import org.json.JSONObject

internal data class GeminiShareTextRequest(val text: String)
internal data class PlainTextShareIntent(val action: String, val mimeType: String, val text: String)

/** Reviewed Android Sharesheet handoff; this never selects a destination or sends content. */
internal object GeminiShareTextPolicy {
    const val TOOL = "share_text"
    const val MAX_LENGTH = 4_000

    fun request(args: JSONObject): GeminiShareTextRequest {
        if (args.length() != 1 || !args.has("text")) throw IOException("Unexpected share-text arguments; no Sharesheet was opened.")
        val raw = args.opt("text") as? String ?: throw IOException("Invalid share text; no Sharesheet was opened.")
        val text = raw.trim()
        if (text.isEmpty() || text.length > MAX_LENGTH || text.any { it.isISOControl() && it !in "\n\r\t" }) {
            throw IOException("Share text must be non-empty, printable, and at most $MAX_LENGTH characters; no Sharesheet was opened.")
        }
        return GeminiShareTextRequest(text)
    }

    fun hasExplicitIntent(userText: String, request: GeminiShareTextRequest): Boolean {
        val text = userText.trim()
        val lower = text.lowercase(Locale.ROOT)
        if (Regex("\\b(don't|do not|never|not)\\s+(share|forward)\\b").containsMatchIn(lower)) return false
        if (Regex("\\b(later|tomorrow|next week|when|if)\\b").containsMatchIn(lower)) return false
        return Regex("\\b(share|forward)\\b").containsMatchIn(lower) && text.contains(request.text)
    }

    fun intent(request: GeminiShareTextRequest): PlainTextShareIntent =
        PlainTextShareIntent("android.intent.action.SEND", "text/plain", request.text)
}
