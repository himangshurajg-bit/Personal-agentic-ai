package com.myra.ultra.nativeapp

/** Pure, bounded image validation and Gemini request serialization; safe to exercise on the JVM. */
internal object GeminiImageRequest {
    const val MAX_IMAGE_BYTES = 4 * 1024 * 1024
    private val allowedMimes = setOf("image/jpeg", "image/png", "image/webp")
    private const val prompt = "Describe this image clearly and concisely. Do not infer sensitive personal attributes."
    private const val alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

    fun validationError(mimeType: String?, bytes: ByteArray?): String? {
        if (mimeType !in allowedMimes) return "Choose a JPEG, PNG, or WebP image."
        if (bytes == null || bytes.isEmpty()) return "The selected image is empty or could not be read."
        if (bytes.size > MAX_IMAGE_BYTES) return "Choose an image no larger than 4 MiB."
        val signatureMatches = when (mimeType) {
            "image/jpeg" -> bytes.size >= 3 && bytes[0] == 0xFF.toByte() && bytes[1] == 0xD8.toByte() && bytes[2] == 0xFF.toByte()
            "image/png" -> bytes.size >= 8 && bytes.take(8).map { it.toInt() and 0xFF } == listOf(137, 80, 78, 71, 13, 10, 26, 10)
            "image/webp" -> bytes.size >= 12 && String(bytes, 0, 4, Charsets.US_ASCII) == "RIFF" && String(bytes, 8, 4, Charsets.US_ASCII) == "WEBP"
            else -> false
        }
        return if (signatureMatches) null else "The file content does not match its image type."
    }

    /** Returns a complete request body, or null when the input is not a supported bounded image. */
    fun buildJson(mimeType: String?, bytes: ByteArray?): String? {
        if (validationError(mimeType, bytes) != null || mimeType == null || bytes == null) return null
        val encoded = base64(bytes)
        return "{\"contents\":[{\"parts\":[{\"text\":\"$prompt\"},{\"inlineData\":{\"mimeType\":\"$mimeType\",\"data\":\"$encoded\"}}]}]}"
    }

    private fun base64(bytes: ByteArray): String = buildString(((bytes.size + 2) / 3) * 4) {
        var i = 0
        while (i < bytes.size) {
            val a = bytes[i++].toInt() and 0xFF
            val hasB = i < bytes.size
            val b = if (hasB) bytes[i++].toInt() and 0xFF else 0
            val hasC = i < bytes.size
            val c = if (hasC) bytes[i++].toInt() and 0xFF else 0
            append(alphabet[a ushr 2])
            append(alphabet[((a and 0x03) shl 4) or (b ushr 4)])
            append(if (hasB) alphabet[((b and 0x0F) shl 2) or (c ushr 6)] else '=')
            append(if (hasC) alphabet[c and 0x3F] else '=')
        }
    }
}
