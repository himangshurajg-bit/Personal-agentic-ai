package com.myra.ultra.nativeapp

import java.util.Locale

/** Validation and latest-turn gate for the user-selected profile name. */
internal object UserNamePreference {
    const val MAX_LENGTH = 30

    fun normalize(value: String): String? {
        val name = value.trim().replace(Regex("\\s+"), " ")
        if (name.isEmpty() || name.length > MAX_LENGTH || name.any(Char::isISOControl)) return null
        return name
    }

    /** Require a direct naming statement that includes the exact proposed name, rejecting negated changes. */
    fun hasExplicitChangeIntent(userText: String, requestedName: String): Boolean {
        val name = normalize(requestedName) ?: return false
        val text = userText.lowercase(Locale.ROOT)
        if (Regex("\\b(?:don't|do not|never|stop|maybe|perhaps)\\b.{0,32}\\b(?:call|set|change|remember|save)\\b")
                .containsMatchIn(text)) return false
        val direct = Regex("\\b(?:call me|my name is|set my name to|change my name to|remember my name as|save my name as)\\b")
            .containsMatchIn(text)
        if (!direct) return false
        val escaped = Regex.escape(name.lowercase(Locale.ROOT))
        return Regex("(?<![\\p{L}\\p{N}])$escaped(?![\\p{L}\\p{N}])")
            .containsMatchIn(text)
    }
}
