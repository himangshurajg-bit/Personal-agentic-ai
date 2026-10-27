package dev.personalagent.personal_assistant

internal const val MAX_LOCAL_OCR_BYTES = 12 * 1024 * 1024
internal const val MAX_LOCAL_OCR_CHARS = 20_000
internal const val MAX_LOCAL_OCR_IMAGE_SIDE = 2048

internal fun supportsLocalOcrMime(mime: String): Boolean =
    mime in setOf("image/jpeg", "image/png", "image/webp")

internal fun boundedLocalOcrText(text: String): String = text.take(MAX_LOCAL_OCR_CHARS)

internal fun localOcrSampleSize(width: Int, height: Int, maxSide: Int = MAX_LOCAL_OCR_IMAGE_SIDE): Int {
    if (width <= 0 || height <= 0 || maxSide <= 0) return 1
    var sample = 1
    while (width / sample > maxSide || height / sample > maxSide) {
        if (sample > Int.MAX_VALUE / 2) return sample
        sample *= 2
    }
    return sample
}
