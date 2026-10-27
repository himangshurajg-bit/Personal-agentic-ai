package com.myra.ultra.nativeapp

import java.util.Locale

/** Battery lookup is limited to a direct current spoken request; Live has separate reviewed actions. */
internal object GeminiLiveBatteryPolicy {
    fun hasExplicitIntent(userText: String): Boolean {
        val text = userText.lowercase(Locale.ROOT)
            .replace(Regex("[^\\p{L}\\p{N}%?]+"), " ")
            .trim()
        if (text.isEmpty() || text.length > 8000) return false
        if (listOf("don t", "do not", "dont", "never", "not yet", "later", "tomorrow", "if i ask", "when i ask", "hypothetical")
                .any(text::contains)) return false
        val hasBattery = Regex("\\b(battery|batteries)\\b").containsMatchIn(text) ||
            Regex("\\b(phone|mobile) (charge|charging)\\b").containsMatchIn(text)
        if (!hasBattery) return false

        // A bare mention or statement is not permission to read device data. Require a direct
        // lookup command or a question containing a concrete battery-status term.
        val lookupCommand = Regex("\\b(check|show|read|tell|batao|bata)\\b").containsMatchIn(text)
        if (lookupCommand) return true
        val statusTerm = Regex("\\b(status|percentage|percent|level|left|remaining|charge|charging|low|high|kitni|kitna|bacha|baki|haal)\\b")
            .containsMatchIn(text)
        val interrogative = text.contains("?") || Regex("^(what|whats|how|hows|is|kitni|kitna|bacha|baki|haal)\\b")
            .containsMatchIn(text)
        return statusTerm && interrogative
    }
}
