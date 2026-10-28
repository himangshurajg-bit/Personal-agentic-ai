package dev.personalagent.personal_assistant

import java.net.URI
import java.net.URLDecoder
import java.nio.charset.StandardCharsets

internal data class UserDownloadTarget(val url: String, val fileName: String)
internal data class UserDownloadRef(val id: Long, val fileName: String) {
    fun encode() = "$id|$fileName"
    companion object {
        fun decode(value: String): UserDownloadRef? {
            val split = value.indexOf('|')
            if (split <= 0 || split == value.lastIndex) return null
            val id = value.substring(0, split).toLongOrNull()?.takeIf { it > 0 } ?: return null
            val name = value.substring(split + 1).takeIf { it.isNotBlank() } ?: return null
            return UserDownloadRef(id, name.take(120))
        }
    }
}

internal object UserDownloadData {
    const val MAX_URL_LENGTH = 2048

    fun validate(raw: String?): UserDownloadTarget? {
        val value = raw?.trim() ?: return null
        if (value.isEmpty() || value.length > MAX_URL_LENGTH || value.any(Char::isISOControl)) return null
        val uri = try { URI(value) } catch (_: Exception) { return null }
        val scheme = uri.scheme?.lowercase() ?: return null
        if (scheme !in setOf("http", "https") || uri.host.isNullOrBlank() || uri.rawUserInfo != null) return null
        val segment = uri.rawPath.orEmpty().substringAfterLast('/').ifBlank { "download" }
        val decoded = try { URLDecoder.decode(segment.replace("+", "%2B"), StandardCharsets.UTF_8.name()) }
        catch (_: Exception) { segment }
        val safeName = decoded
            .replace(Regex("[^A-Za-z0-9._() -]"), "_")
            .trim().trim('.')
            .take(120)
            .ifBlank { "download" }
        return UserDownloadTarget(uri.toASCIIString(), safeName)
    }

    fun safeFileName(requested: String?, fallback: String): String {
        val candidate = requested.orEmpty()
            .replace(Regex("[^A-Za-z0-9._() -]"), "_")
            .trim().trim('.')
            .take(120)
            .ifBlank { fallback }
        return candidate.takeIf { it.isNotBlank() && it != "." && it != ".." } ?: "download"
    }

    fun uniqueFileName(name: String, existing: Set<String>): String {
        if (name !in existing) return name
        val dot = name.lastIndexOf('.').takeIf { it > 0 } ?: name.length
        val stem = name.substring(0, dot)
        val extension = name.substring(dot)
        var index = 2
        while (index < 10000) {
            val suffix = " ($index)"
            val candidate = stem.take((120 - extension.length - suffix.length).coerceAtLeast(1)) + suffix + extension
            if (candidate !in existing) return candidate
            index++
        }
        return stem.take(100) + "-" + System.currentTimeMillis() + extension.take(20)
    }

    fun progress(done: Long, total: Long): Int? =
        if (done < 0 || total <= 0) null else ((done.coerceAtMost(total).toDouble() / total) * 100).toInt().coerceIn(0, 100)
}
