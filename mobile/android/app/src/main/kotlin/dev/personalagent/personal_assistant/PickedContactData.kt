package dev.personalagent.personal_assistant

/** Bounded values from exactly one row explicitly chosen in Android's contact picker. */
internal data class PickedContactData(val displayName: String, val phoneNumber: String)

internal object PickedContactDataParser {
    const val MAX_NAME_LENGTH = 120
    const val MAX_PHONE_LENGTH = 48

    fun parse(name: String?, number: String?): PickedContactData? {
        val safeName = name?.trim() ?: return null
        val safeNumber = number?.trim() ?: return null
        if (safeName.isEmpty() || safeName.length > MAX_NAME_LENGTH ||
            safeNumber.isEmpty() || safeNumber.length > MAX_PHONE_LENGTH) return null
        if (safeName.any(Char::isISOControl) || safeNumber.any(Char::isISOControl)) return null
        if (safeNumber.count(Char::isDigit) !in 3..20) return null
        if (safeNumber.any { !(it.isDigit() || it in "+-(). /#*extEXT,;") }) return null
        return PickedContactData(safeName, safeNumber)
    }
}
