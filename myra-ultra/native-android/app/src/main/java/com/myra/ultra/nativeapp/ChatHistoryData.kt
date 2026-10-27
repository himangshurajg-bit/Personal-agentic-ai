package com.myra.ultra.nativeapp

import org.json.JSONArray
import org.json.JSONObject

/** Bounded on-device chat-history codec shared by normal saves and the explicit clear action. */
internal object ChatHistoryData {
    const val MAX_MESSAGES = 100
    const val MAX_MESSAGE_CHARS = 8_000

    fun decode(serialized: String?): List<Pair<Boolean, String>> = try {
        val json = JSONArray(serialized ?: "[]")
        (0 until json.length()).mapNotNull { index ->
            val item = json.optJSONObject(index) ?: return@mapNotNull null
            item.optString("text").takeIf { it.isNotBlank() }
                ?.let { item.optBoolean("user") to it.take(MAX_MESSAGE_CHARS) }
        }.takeLast(MAX_MESSAGES)
    } catch (_: Exception) {
        emptyList()
    }

    fun encode(messages: List<Pair<Boolean, String>>): String {
        val json = JSONArray()
        messages.takeLast(MAX_MESSAGES).forEach { (user, text) ->
            json.put(JSONObject().put("user", user).put("text", text.take(MAX_MESSAGE_CHARS)))
        }
        return json.toString()
    }
}
