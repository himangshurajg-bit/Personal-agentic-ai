package com.myra.ultra.nativeapp

import java.util.Locale
import org.json.JSONObject

/** Limits Clock timer handoffs to one plainly stated duration in the latest direct request. */
internal object GeminiTimerPolicy {
    const val TOOL = "set_timer"
    private val durationPattern = Regex("(?<![0-9])([0-9]{1,5})\\s*(seconds?|secs?|minutes?|mins?|hours?|hrs?)(?![a-z])", RegexOption.IGNORE_CASE)
    private val requestPattern = Regex("\\b(?:set|start|create)\\s+(?:a\\s+)?timer\\s+(?:for|of)\\b", RegexOption.IGNORE_CASE)
    private val disallowedPattern = Regex("\\b(?:don't|do not|never|cancel|not|if|when|tomorrow|daily|every|later|next|schedule|remind|alarm)\\b", RegexOption.IGNORE_CASE)

    fun request(args: JSONObject): ClockTimerRequest? {
        if (args.length() != 1 || !args.has("seconds") || args.opt("seconds") !is Int) return null
        return ClockTimerData.parse(args.getInt("seconds").toString(), "MYRA")
    }

    /** Exact numeric duration and one direct request are required; no delayed/repeating timer semantics. */
    fun hasExplicitIntent(userText: String, request: ClockTimerRequest): Boolean {
        val text = userText.lowercase(Locale.ROOT)
        if (disallowedPattern.containsMatchIn(text) || !requestPattern.containsMatchIn(text)) return false
        val matches = durationPattern.findAll(userText).toList()
        if (matches.size != 1) return false
        val match = matches.single()
        val amount = match.groupValues[1].toIntOrNull() ?: return false
        val unit = match.groupValues[2].lowercase(Locale.ROOT)
        val multiplier = when {
            unit.startsWith("sec") -> 1
            unit.startsWith("min") -> 60
            else -> 3600
        }
        val seconds = amount.toLong() * multiplier
        return seconds in ClockTimerData.MIN_SECONDS.toLong()..ClockTimerData.MAX_SECONDS.toLong() && request.seconds == seconds.toInt()
    }
}
