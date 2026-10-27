package com.myra.ultra.nativeapp

import java.net.URI
import java.net.URLDecoder
import java.nio.charset.StandardCharsets

internal data class DownloadTarget(val url: String, val fileName: String)

internal object DownloadData {
    const val MAX_URL_LENGTH = 2048
    const val MAX_FILE_NAME_LENGTH = 120

    fun validate(raw: String): DownloadTarget? {
        val value = raw.trim()
        if (value.isEmpty() || value.length > MAX_URL_LENGTH || value.any { it.isISOControl() }) return null
        val uri = try { URI(value) } catch (_: Exception) { return null }
        val scheme = uri.scheme?.lowercase() ?: return null
        if (scheme !in setOf("http", "https") || uri.host.isNullOrBlank() || uri.rawUserInfo != null) return null
        val pathPart = uri.rawPath.orEmpty().substringAfterLast('/').ifBlank { "myra-download" }
        val decoded = try { URLDecoder.decode(pathPart.replace("+", "%2B"), StandardCharsets.UTF_8.name()) } catch (_: Exception) { pathPart }
        val safe = decoded
            .replace(Regex("[^\\p{L}\\p{N}._() -]"), "_")
            .trim().trim('.').take(MAX_FILE_NAME_LENGTH)
            .ifBlank { "myra-download" }
        return DownloadTarget(uri.toASCIIString(), safe)
    }
}

internal data class DownloadRef(val id: Long, val fileName: String) {
    fun encode(): String = "$id|$fileName"

    companion object {
        fun decode(value: String): DownloadRef? {
            val divider = value.indexOf('|')
            if (divider <= 0 || divider == value.lastIndex) return null
            val id = value.substring(0, divider).toLongOrNull() ?: return null
            val name = value.substring(divider + 1).takeIf(String::isNotBlank) ?: return null
            return DownloadRef(id, name)
        }
    }
}

enum class LocalDownloadStatus { PENDING, RUNNING, PAUSED, COMPLETE, FAILED, UNKNOWN }

internal data class DownloadSnapshot(
    val ref: DownloadRef,
    val status: LocalDownloadStatus,
    val percent: Int?,
    val detail: String,
    val canOpen: Boolean,
)

internal fun downloadProgress(done: Long, total: Long): Int? =
    if (done < 0 || total <= 0) null else ((done.coerceAtMost(total).toDouble() / total.toDouble()) * 100.0).toInt().coerceIn(0, 100)

internal fun downloadStatusLabel(status: LocalDownloadStatus, percent: Int?, reason: Int = 0): String = when (status) {
    LocalDownloadStatus.PENDING -> "Waiting to download"
    LocalDownloadStatus.RUNNING -> percent?.let { "Downloading · $it%" } ?: "Downloading"
    LocalDownloadStatus.PAUSED -> "Paused by Android (reason $reason)"
    LocalDownloadStatus.COMPLETE -> "Downloaded"
    LocalDownloadStatus.FAILED -> "Download failed (reason $reason)"
    LocalDownloadStatus.UNKNOWN -> "Status unavailable"
}
