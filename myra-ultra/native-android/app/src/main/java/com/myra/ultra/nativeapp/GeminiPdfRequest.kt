package com.myra.ultra.nativeapp

/** Bounded PDF validation and Gemini inline-data request construction. */
internal object GeminiPdfRequest {
    const val MAX_PDF_BYTES = 4 * 1024 * 1024
    private const val prefix = "%PDF-"
    private const val defaultPrompt = "Summarize this PDF accurately. Separate what the document states from any uncertainty; do not invent missing details."
    private const val alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

    fun validationError(mimeType: String?, bytes: ByteArray?): String? {
        if (mimeType != "application/pdf") return "Choose a PDF document."
        if (bytes == null || bytes.isEmpty()) return "The selected PDF is empty or could not be read."
        if (bytes.size > MAX_PDF_BYTES) return "Choose a PDF no larger than 4 MiB."
        val signatureMatches = bytes.size >= prefix.length &&
            String(bytes, 0, prefix.length, Charsets.US_ASCII) == prefix
        return if (signatureMatches) null else "The selected file does not have a valid PDF signature."
    }

    /** Returns a request body only for a bounded PDF with the expected signature. */
    fun buildJson(bytes: ByteArray?, prompt: String = defaultPrompt): String? {
        if (validationError("application/pdf", bytes) != null || bytes == null) return null
        val safePrompt = prompt.trim().take(600).ifBlank { defaultPrompt }
        val encoded = base64(bytes)
        return "{\"contents\":[{\"parts\":[{\"text\":${jsonString(safePrompt)}},{\"inlineData\":{\"mimeType\":\"application/pdf\",\"data\":\"$encoded\"}}]}]}"
    }

    private fun jsonString(value: String): String = buildString(value.length + 2) {
        append('"')
        value.forEach { ch ->
            when (ch) {
                '"' -> append("\\\"")
                '\\' -> append("\\\\")
                '\b' -> append("\\b")
                '\u000C' -> append("\\f")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                '\t' -> append("\\t")
                else -> if (ch.code < 0x20) append("\\u%04x".format(ch.code)) else append(ch)
            }
        }
        append('"')
    }

    private fun base64(bytes: ByteArray): String = buildString(((bytes.size + 2) / 3) * 4) {
        var index = 0
        while (index < bytes.size) {
            val a = bytes[index++].toInt() and 0xFF
            val hasB = index < bytes.size
            val b = if (hasB) bytes[index++].toInt() and 0xFF else 0
            val hasC = index < bytes.size
            val c = if (hasC) bytes[index++].toInt() and 0xFF else 0
            append(alphabet[a ushr 2])
            append(alphabet[((a and 0x03) shl 4) or (b ushr 4)])
            append(if (hasB) alphabet[((b and 0x0F) shl 2) or (c ushr 6)] else '=')
            append(if (hasC) alphabet[c and 0x3F] else '=')
        }
    }
}
