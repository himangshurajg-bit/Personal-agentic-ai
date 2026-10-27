package com.myra.ultra.nativeapp

/** Values returned for one contact row explicitly selected through Android's picker. */
internal data class PickedContact(val displayName: String, val phoneNumber: String)

internal object ContactLookupData {
    const val MAX_NAME_LENGTH = 120
    const val MAX_PHONE_LENGTH = 48

    /** Bound and sanitize picker results before displaying them; no address-book search is performed here. */
    fun parse(name: String?, number: String?): PickedContact? {
        val cleanName = name?.trim() ?: return null
        val cleanNumber = number?.trim() ?: return null
        if (cleanName.isEmpty() || cleanName.length > MAX_NAME_LENGTH || cleanNumber.isEmpty() || cleanNumber.length > MAX_PHONE_LENGTH) return null
        if (cleanName.any(Char::isISOControl) || cleanNumber.any(Char::isISOControl)) return null
        val digits = cleanNumber.count(Char::isDigit)
        if (digits !in 3..20 || cleanNumber.any { !(it.isDigit() || it in "+-(). /#*extEXT,;" ) }) return null
        return PickedContact(cleanName, cleanNumber)
    }
}
