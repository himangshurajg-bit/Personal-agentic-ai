package com.myra.ultra.nativeapp

import java.util.Locale
import org.json.JSONObject

internal object GeminiAlarmPolicy {
    const val TOOL = "set_alarm"
    private val timePattern = Regex("(?<![0-9])([01][0-9]|2[0-3]):([0-5][0-9])(?![0-9])")

    fun request(args: JSONObject): ClockAlarmRequest? {
        if (args.length() != 2 || !args.has("hour") || !args.has("minute") ||
            args.opt("hour") !is Int || args.opt("minute") !is Int) return null
        val hour = args.getInt("hour")
        val minute = args.getInt("minute")
        return ClockAlarmData.parse(hour.toString(), minute.toString(), "")
    }

    /** Only permit a one-off alarm for one exact 24-hour time stated in a direct latest-turn request. */
    fun hasExplicitIntent(userText: String, request: ClockAlarmRequest): Boolean {
        val text = userText.lowercase(Locale.ROOT)
        if (Regex("\\b(?:don't|do not|never|cancel|not)\\b|\\b(?:if|when|tomorrow|daily|every|later|next week|schedule|remind)\\b").containsMatchIn(text)) return false
        if (!Regex("\\b(?:set|create)\\s+(?:an?\\s+)?alarm\\s+(?:for|at)\\b").containsMatchIn(text)) return false
        val times = timePattern.findAll(userText).toList()
        if (times.size != 1) return false
        val match = times.single()
        val hour = match.groupValues[1].toIntOrNull() ?: return false
        val minute = match.groupValues[2].toIntOrNull() ?: return false
        return request.hour == hour && request.minute == minute
    }
}
