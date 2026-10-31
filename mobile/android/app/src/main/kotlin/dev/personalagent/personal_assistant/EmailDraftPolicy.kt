package dev.personalagent.personal_assistant

import java.net.URLEncoder
import java.nio.charset.StandardCharsets

internal data class EmailDraftRequest(val recipient: String, val subject: String, val body: String)

internal object EmailDraftPolicy {
    const val MAX_SUBJECT_LENGTH = 200
    const val MAX_BODY_LENGTH = 10_000
    private val email = Regex("[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\\.[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+)*@" +
        "[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*")

    fun parse(recipientValue: Any?, subjectValue: Any?, bodyValue: Any?): EmailDraftRequest? {
        val recipient = (recipientValue as? String)?.trim() ?: return null
        val subject = subjectValue as? String ?: return null
        val body = bodyValue as? String ?: return null
        if (recipient.length !in 3..254 || !email.matches(recipient) ||
            subject.length > MAX_SUBJECT_LENGTH || subject.any { it.isISOControl() } ||
            body.isBlank() || body.length > MAX_BODY_LENGTH ||
            body.any { it.isISOControl() && it != '\n' && it != '\r' && it != '\t' }) return null
        return EmailDraftRequest(recipient, subject, body)
    }

    /** Builds one recipient-only mailto URI; it can open a composer but cannot send. */
    fun mailto(request: EmailDraftRequest): String {
        fun encode(value: String) = URLEncoder.encode(value, StandardCharsets.UTF_8.name()).replace("+", "%20")
        return "mailto:${request.recipient}?subject=${encode(request.subject)}&body=${encode(request.body)}"
    }
}
