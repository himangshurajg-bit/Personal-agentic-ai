package com.myra.ultra.nativeapp

import java.net.URLDecoder
import java.net.URLEncoder
import java.nio.charset.CodingErrorAction
import okio.ByteString.Companion.decodeBase64
import okio.ByteString.Companion.toByteString
import org.json.JSONArray
import org.json.JSONObject

/** Offline text transformations. Inputs and outputs are bounded and never persisted or transmitted. */
internal enum class TextUtilityOperation(val label: String) {
    BASE64_ENCODE("Base64 encode"),
    BASE64_DECODE("Base64 decode"),
    URL_ENCODE("URL form encode"),
    URL_DECODE("URL form decode"),
    JSON_PRETTY("JSON pretty-print"),
    JSON_MINIFY("JSON minify"),
}

internal object TextUtility {
    const val MAX_INPUT_CHARS = 64 * 1024
    const val MAX_OUTPUT_CHARS = 128 * 1024
    private const val MAX_JSON_DEPTH = 32

    fun transform(operation: TextUtilityOperation, input: String): String {
        require(input.length <= MAX_INPUT_CHARS) { "Input is too large (maximum 64 KiB of text)." }
        val result = when (operation) {
            TextUtilityOperation.BASE64_ENCODE -> input.toByteArray(Charsets.UTF_8).toByteString().base64()
            TextUtilityOperation.BASE64_DECODE -> {
                val bytes = input.trim().decodeBase64()?.toByteArray()
                    ?: throw IllegalArgumentException("Enter valid standard Base64 text.")
                try {
                    Charsets.UTF_8.newDecoder()
                        .onMalformedInput(CodingErrorAction.REPORT)
                        .onUnmappableCharacter(CodingErrorAction.REPORT)
                        .decode(java.nio.ByteBuffer.wrap(bytes)).toString()
                } catch (_: Exception) {
                    throw IllegalArgumentException("Decoded bytes are not valid UTF-8 text.")
                }
            }
            TextUtilityOperation.URL_ENCODE -> URLEncoder.encode(input, Charsets.UTF_8.name())
            TextUtilityOperation.URL_DECODE -> try {
                URLDecoder.decode(input, Charsets.UTF_8.name())
            } catch (_: IllegalArgumentException) {
                throw IllegalArgumentException("Enter valid percent-encoded URL form text.")
            }
            TextUtilityOperation.JSON_PRETTY, TextUtilityOperation.JSON_MINIFY -> formatJson(input, operation == TextUtilityOperation.JSON_PRETTY)
        }
        require(result.length <= MAX_OUTPUT_CHARS) { "Output is too large to display safely." }
        return result
    }

    private fun formatJson(input: String, pretty: Boolean): String {
        val text = input.trim()
        require(text.isNotEmpty()) { "Enter a JSON object or array." }
        val value: Any = try {
            if (text.startsWith("{")) JSONObject(text) else if (text.startsWith("[")) JSONArray(text)
            else throw IllegalArgumentException("Only a JSON object or array is supported.")
        } catch (error: IllegalArgumentException) {
            throw error
        } catch (_: Exception) {
            throw IllegalArgumentException("That JSON is malformed.")
        }
        require(maxDepth(value, 0) <= MAX_JSON_DEPTH) { "JSON nesting is too deep (maximum 32 levels)." }
        return try {
            when (value) {
                is JSONObject -> if (pretty) value.toString(2) else value.toString()
                is JSONArray -> if (pretty) value.toString(2) else value.toString()
                else -> throw IllegalArgumentException("Only a JSON object or array is supported.")
            }
        } catch (_: Exception) {
            throw IllegalArgumentException("Could not format this JSON safely.")
        }
    }

    private fun maxDepth(value: Any, depth: Int): Int {
        if (depth > MAX_JSON_DEPTH) return depth
        return when (value) {
            is JSONObject -> {
                var result = depth
                val keys = value.keys()
                while (keys.hasNext()) result = maxOf(result, maxDepth(value.get(keys.next()), depth + 1))
                result
            }
            is JSONArray -> {
                var result = depth
                for (index in 0 until value.length()) result = maxOf(result, maxDepth(value.get(index), depth + 1))
                result
            }
            else -> depth
        }
    }
}
