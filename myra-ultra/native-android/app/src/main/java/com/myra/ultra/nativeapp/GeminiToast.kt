package com.myra.ultra.nativeapp

import java.io.IOException
import java.util.Locale
import org.json.JSONObject

/** Bounded, review-gated short in-app message, matching the prototype's toast tool. */
internal object GeminiToastPolicy {
    const val TOOL = "show_toast"
    private const val MAX_LENGTH = 120

    fun request(args: JSONObject): GeminiToastRequest {
        if (args.length() != 1 || !args.has("text")) {
            throw IOException("Gemini requested unexpected toast arguments; no message was shown.")
        }
        val text = args.opt("text") as? String
            ?: throw IOException("Gemini requested invalid toast text; no message was shown.")
        if (text.isBlank() || text.length > MAX_LENGTH || text.any { it.isISOControl() }) {
            throw IOException("Toast text must be 1–120 printable characters; no message was shown.")
        }
        return GeminiToastRequest(text)
    }

    fun hasExplicitIntent(userText: String, request: GeminiToastRequest): Boolean {
        val normalized = userText.lowercase(Locale.ROOT)
        if (Regex("\\b(?:don't|do not|never|not)\\s+(?:show|display)\\b").containsMatchIn(normalized)) return false
        val asksForToast = Regex("\\b(?:show|display)\\b.{0,40}\\btoast\\b|\\btoast\\b.{0,40}\\b(?:show|display)\\b").containsMatchIn(normalized)
        return asksForToast && userText.contains(request.text)
    }
}
