package com.myra.ultra.nativeapp

import android.content.Context
import android.graphics.Bitmap
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import java.io.IOException
import kotlin.math.roundToInt

/** Renders one user-selected PDF page locally, with only one bounded bitmap at a time. */
internal object LocalPdfPreview {
    data class Page(val index: Int, val count: Int, val bitmap: Bitmap)
    const val MAX_EDGE_PX = 1_600

    fun pageBitmapSize(pageWidth: Int, pageHeight: Int, maxEdgePx: Int = MAX_EDGE_PX): Pair<Int, Int>? {
        if (pageWidth <= 0 || pageHeight <= 0 || maxEdgePx <= 0) return null
        val scale = minOf(1.0, maxEdgePx.toDouble() / maxOf(pageWidth, pageHeight))
        val width = (pageWidth * scale).roundToInt().coerceIn(1, maxEdgePx)
        val height = (pageHeight * scale).roundToInt().coerceIn(1, maxEdgePx)
        return width to height
    }

    fun pageIndexOrNull(index: Int, pageCount: Int): Int? =
        index.takeIf { pageCount > 0 && it in 0 until pageCount }

    fun renderFirstPage(context: Context, uri: Uri): Bitmap = renderPage(context, uri, 0).bitmap

    fun renderPage(context: Context, uri: Uri, index: Int): Page {
        val descriptor = context.contentResolver.openFileDescriptor(uri, "r")
            ?: throw IOException("This PDF could not be opened for local preview.")
        return descriptor.use { fileDescriptor ->
            PdfRenderer(fileDescriptor).use { renderer ->
                val pageIndex = pageIndexOrNull(index, renderer.pageCount)
                    ?: throw IOException("This PDF page is outside the document's page range.")
                renderer.openPage(pageIndex).use { page ->
                    val (width, height) = pageBitmapSize(page.width, page.height)
                        ?: throw IOException("This PDF page has invalid dimensions.")
                    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                    try {
                        bitmap.eraseColor(android.graphics.Color.WHITE)
                        page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                        Page(pageIndex, renderer.pageCount, bitmap)
                    } catch (error: Exception) {
                        bitmap.recycle()
                        throw error
                    }
                }
            }
        }
    }
}
