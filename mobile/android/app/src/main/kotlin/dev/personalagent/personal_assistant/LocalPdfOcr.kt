package dev.personalagent.personal_assistant

internal const val MAX_LOCAL_PDF_OCR_BYTES = 12 * 1024 * 1024
internal const val MAX_LOCAL_PDF_OCR_PAGES = 8
internal const val MAX_LOCAL_PDF_OCR_CHARS = 20_000
internal const val MAX_LOCAL_PDF_OCR_SIDE = 2048

internal fun localPdfOcrPageLimit(pageCount: Int): Int =
    pageCount.coerceAtLeast(0).coerceAtMost(MAX_LOCAL_PDF_OCR_PAGES)

internal fun localPdfOcrBitmapSize(width: Int, height: Int, maxSide: Int = MAX_LOCAL_PDF_OCR_SIDE): Pair<Int, Int>? {
    if (width <= 0 || height <= 0 || maxSide <= 0) return null
    val scale = minOf(1.0, maxSide.toDouble() / maxOf(width, height).toDouble())
    return (width * scale).toInt().coerceAtLeast(1) to (height * scale).toInt().coerceAtLeast(1)
}

internal fun appendBoundedPdfPage(existing: String, pageNumber: Int, text: String): String {
    if (existing.length >= MAX_LOCAL_PDF_OCR_CHARS) return existing.take(MAX_LOCAL_PDF_OCR_CHARS)
    val prefix = "Page $pageNumber\n"
    val separator = if (existing.isEmpty()) "" else "\n\n"
    val remaining = MAX_LOCAL_PDF_OCR_CHARS - existing.length - separator.length - prefix.length
    if (remaining <= 0) return (existing + separator + prefix).take(MAX_LOCAL_PDF_OCR_CHARS)
    return existing + separator + prefix + text.take(remaining)
}

internal fun pdfPageTextWouldTruncate(existing: String, pageNumber: Int, text: String): Boolean {
    val prefix = "Page $pageNumber\n"
    val separatorLength = if (existing.isEmpty()) 0 else 2
    val available = (MAX_LOCAL_PDF_OCR_CHARS - existing.length - separatorLength - prefix.length).coerceAtLeast(0)
    return text.length > available
}
