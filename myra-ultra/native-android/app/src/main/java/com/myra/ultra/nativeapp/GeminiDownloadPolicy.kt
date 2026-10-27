package com.myra.ultra.nativeapp

import java.io.IOException
import java.util.Locale
import org.json.JSONObject

internal data class GeminiDownloadRequest(val target: DownloadTarget) {
    val url: String get() = target.url
    val fileName: String get() = target.fileName
}

/** Restricts Gemini's download handoff to a URL supplied with a direct request in the latest turn. */
internal object GeminiDownloadPolicy {
    const val TOOL = "download_file"

    fun request(args: JSONObject): GeminiDownloadRequest {
        if (args.length() != 1 || !args.has("url")) {
            throw IOException("Gemini requested unexpected download arguments; no download was started.")
        }
        val rawUrl = args.opt("url") as? String
            ?: throw IOException("Gemini requested an invalid download URL; no download was started.")
        val target = DownloadData.validate(rawUrl)
            ?: throw IOException("Gemini requested an unsupported or invalid HTTP(S) URL; no download was started.")
        return GeminiDownloadRequest(target)
    }

    fun hasExplicitIntent(userText: String, request: GeminiDownloadRequest): Boolean {
        if (!userText.contains(request.url)) return false
        val text = userText.lowercase(Locale.ROOT)
        if (Regex("\\b(?:don't|do not|never|not)\\b.{0,48}\\b(?:download|save|fetch)\\b").containsMatchIn(text)) return false
        if (Regex("\\b(?:if|when|whenever|later|tomorrow|schedule|remind|after|before)\\b").containsMatchIn(text)) return false
        return Regex("\\b(?:download|save|fetch)\\b").containsMatchIn(text)
    }
}
