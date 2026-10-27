package com.myra.ultra.nativeapp

import java.io.IOException
import java.io.Reader
import org.json.JSONException
import org.json.JSONObject

internal sealed class GeminiSseEvent {
    data class Text(val value: String) : GeminiSseEvent()
    data class FunctionCall(val name: String, val args: JSONObject, val id: String? = null, val modelContent: JSONObject) : GeminiSseEvent()
}


/** Reads SSE lines incrementally so an unterminated network line cannot grow without bound. */
internal class BoundedSseLineReader(
    private val reader: Reader,
    private val maxLineChars: Int = GeminiSseParser.MAX_EVENT_CHARS + 6
) {
    private var pendingChar: Int? = null

    init {
        require(maxLineChars >= 0)
    }

    fun readLine(): String? {
        val line = StringBuilder(minOf(maxLineChars, 256))
        var sawInput = false
        while (true) {
            val value = pendingChar?.also { pendingChar = null } ?: reader.read()
            if (value < 0) return if (sawInput) line.toString() else null
            sawInput = true
            when (value.toChar()) {
                '\n' -> return line.toString()
                '\r' -> {
                    val following = reader.read()
                    if (following >= 0 && following != '\n'.code) pendingChar = following
                    return line.toString()
                }
                else -> {
                    if (line.length >= maxLineChars) {
                        throw IOException("Gemini sent an oversized stream line.")
                    }
                    line.append(value.toChar())
                }
            }
        }
    }
}

/** Parses JSON `data:` events returned by Gemini streamGenerateContent SSE. */
internal class GeminiSseParser(
    private val maxEventChars: Int = MAX_EVENT_CHARS
) {
    init {
        require(maxEventChars >= 0)
    }

    private val dataLines = mutableListOf<String>()
    private var bufferedChars = 0

    fun acceptLine(line: String): List<GeminiSseEvent> {
        if (line.isEmpty()) return dispatchEvent()
        if (line.startsWith(':')) return emptyList()
        val colon = line.indexOf(':')
        val field = if (colon < 0) line else line.substring(0, colon)
        if (field != "data") return emptyList()
        var value = if (colon < 0) "" else line.substring(colon + 1)
        if (value.startsWith(' ')) value = value.substring(1)
        bufferedChars += value.length + if (dataLines.isEmpty()) 0 else 1
        if (bufferedChars > maxEventChars) throw IOException("Gemini sent an oversized stream event.")
        dataLines += value
        return emptyList()
    }

    fun finish(): List<GeminiSseEvent> = dispatchEvent()

    private fun dispatchEvent(): List<GeminiSseEvent> {
        if (dataLines.isEmpty()) return emptyList()
        val data = dataLines.joinToString("\n")
        dataLines.clear()
        bufferedChars = 0
        val json = try {
            JSONObject(data)
        } catch (error: JSONException) {
            throw IOException("Gemini returned an invalid stream event.", error)
        }
        val apiError = json.optJSONObject("error")
        if (apiError != null) {
            val message = apiError.optString("message").take(240).ifBlank { "Gemini returned a stream error." }
            throw IOException(message)
        }
        val candidates = json.optJSONArray("candidates") ?: return emptyList()
        val modelContent = candidates.optJSONObject(0)?.optJSONObject("content") ?: return emptyList()
        val parts = modelContent.optJSONArray("parts") ?: return emptyList()
        return buildList {
            for (index in 0 until parts.length()) {
                val part = parts.optJSONObject(index) ?: continue
                part.optString("text").takeIf { it.isNotEmpty() && it != "null" }?.let { add(GeminiSseEvent.Text(it)) }
                val call = part.optJSONObject("functionCall") ?: continue
                val name = call.optString("name").takeIf(String::isNotBlank)
                    ?: throw IOException("Gemini returned a function call without a name.")
                val args = call.optJSONObject("args") ?: JSONObject()
                add(GeminiSseEvent.FunctionCall(name, args, call.optString("id").takeIf { it.isNotBlank() && it != "null" }, JSONObject(modelContent.toString())))
            }
        }
    }

    internal companion object {
        const val MAX_EVENT_CHARS = 1_000_000
    }
}
