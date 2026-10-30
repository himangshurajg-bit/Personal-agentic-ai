package dev.personalagent.personal_assistant

internal data class UserNotificationRequest(val title: String, val text: String)

/** Validates the exact, user-entered payload passed across the Android bridge. */
internal object UserNotificationRequestParser {
    const val TITLE_LIMIT = 80
    const val TEXT_LIMIT = 300

    fun parse(arguments: Map<*, *>?): UserNotificationRequest? {
        if (arguments == null || arguments.size != 2 ||
            !arguments.containsKey("title") || !arguments.containsKey("text")) return null
        val title = arguments["title"] as? String ?: return null
        val text = arguments["text"] as? String ?: return null
        if (title.isBlank() || title.length > TITLE_LIMIT || title.any { it.isISOControl() }) return null
        if (text.isBlank() || text.length > TEXT_LIMIT ||
            text.any { it.isISOControl() && it != '\n' && it != '\r' && it != '\t' }) return null
        return UserNotificationRequest(title, text)
    }
}
