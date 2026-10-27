package com.myra.ultra.nativeapp

data class ClipboardPreview(val text: String, val truncated: Boolean)

object ClipboardPreviewData {
    const val MAX_CHARS = 4_000

    /** Keep only a bounded local text preview; never coerce URI or other clipboard items to text. */
    fun fromText(value: CharSequence?): ClipboardPreview? {
        if (value == null || value.isEmpty()) return null
        val text = value.toString()
        var end = minOf(text.length, MAX_CHARS)
        // Avoid returning half of a UTF-16 surrogate pair at the preview boundary.
        if (end < text.length && end > 0 && text[end - 1].isHighSurrogate() && text[end].isLowSurrogate()) end--
        return ClipboardPreview(text.substring(0, end), text.length > end)
    }
}
