package com.myra.ultra.nativeapp

import java.io.IOException
import java.util.Locale
import org.json.JSONObject

internal data class GeminiClipboardReadRequest(val preview: ClipboardPreview)

/** The model may request a one-time read only after an explicit latest-turn request. */
internal object GeminiClipboardReadPolicy {
    const val TOOL = "read_clipboard_text"

    fun validateArguments(args: JSONObject) {
        if (args.length() != 0) throw IOException("Gemini requested unexpected clipboard-read arguments; the clipboard was not read.")
    }

    fun request(value: CharSequence?): GeminiClipboardReadRequest? =
        ClipboardPreviewData.fromText(value)?.let(::GeminiClipboardReadRequest)

    /** Require an immediate direct request, not a how-to question, negation, or future suggestion. */
    fun hasExplicitIntent(userText: String): Boolean {
        val text = userText.lowercase(Locale.ROOT).replace(Regex("\\s+"), " ").trim()
        if (!Regex("\\bclipboard\\b").containsMatchIn(text)) return false
        if (Regex("\\b(?:don't|do not|never|not|without|stop|cancel|later|tomorrow|next time|if i ask|when i ask)\\b")
                .containsMatchIn(text)) return false
        if (Regex("\\bhow (?:do|can|to) i\\b|\\bexplain\\b|\\bwhat app\\b").containsMatchIn(text)) return false
        val directVerb = Regex("\\b(?:read|show|display|see|view|check)\\b[^.!?;]{0,45}\\bclipboard\\b")
            .containsMatchIn(text)
        val directQuestion = Regex("\\bwhat(?:'s| is) (?:in|on) (?:my )?clipboard\\b|\\bwhat is in my clipboard\\b")
            .containsMatchIn(text)
        val reverseOrder = Regex("\\bclipboard\\b[^.!?;]{0,30}\\b(?:read|show|display|see|view)\\b")
            .containsMatchIn(text)
        return directVerb || directQuestion || reverseOrder
    }
}
