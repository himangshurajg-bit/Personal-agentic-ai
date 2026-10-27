package com.myra.ultra.nativeapp

import java.util.Locale

/** Voice-action gates bind a model call to one direct spoken request and its exact requested value. */
internal object GeminiLiveActionPolicy {
    fun hasExplicitVolumeIntent(userText: String, request: GeminiVolumeRequest): Boolean {
        val text = userText.lowercase(Locale.ROOT)
        if (Regex("\\b(?:don't|do not|never|not)\\b.{0,32}\\b(?:set|change|adjust|raise|lower|increase|decrease|turn)\\b").containsMatchIn(text)) return false
        if (Regex("\\b(?:if|when|whenever|later|tomorrow|schedule|remind|after|before)\\b").containsMatchIn(text)) return false
        if (!Regex("\\bvolume\\b").containsMatchIn(text)) return false
        val directChange = Regex("\\b(?:set|change|adjust|raise|lower|increase|decrease|turn)\\b.{0,40}\\bvolume\\b|\\bvolume\\b.{0,24}\\b(?:to|at)\\b").containsMatchIn(text)
        if (!directChange) return false
        val streamTerms = when (request.stream) {
            MyraVolumeStream.MUSIC -> listOf("music")
            MyraVolumeStream.RING -> listOf("ring", "ringtone")
            MyraVolumeStream.ALARM -> listOf("alarm")
            MyraVolumeStream.NOTIFICATION -> listOf("notification")
            MyraVolumeStream.SYSTEM -> listOf("system")
            MyraVolumeStream.CALL -> listOf("call", "voice call")
        }
        if (streamTerms.none { Regex("\\b${Regex.escape(it)}\\b").containsMatchIn(text) }) return false
        val percentMentions = Regex("(?<![A-Za-z0-9])\\d{1,3}(?![A-Za-z0-9])(?:\\s*(?:%|percent|per cent))?", RegexOption.IGNORE_CASE)
            .findAll(userText).toList()
        if (percentMentions.size != 1) return false
        val mention = percentMentions.single()
        val value = Regex("^\\s*(\\d{1,3})", RegexOption.IGNORE_CASE).find(mention.value)?.groupValues?.get(1)?.toIntOrNull()
            ?: return false
        val includesPercentUnit = Regex("(?:%|percent|per cent)", RegexOption.IGNORE_CASE).containsMatchIn(mention.value)
        return includesPercentUnit && value == request.percent
    }

    fun hasExplicitBrightnessIntent(userText: String, request: GeminiBrightnessRequest): Boolean {
        val text = userText.lowercase(Locale.ROOT)
        if (Regex("\\b(?:if|when|whenever|later|tomorrow|schedule|remind|after|before|daily|every)\\b").containsMatchIn(text)) return false
        return GeminiSafeTools.hasExplicitBrightnessIntent(userText, request.level)
    }

    fun hasExplicitTorchIntent(userText: String, turnOn: Boolean): Boolean =
        GeminiSafeTools.hasExplicitTorchIntent(userText, turnOn)
}
