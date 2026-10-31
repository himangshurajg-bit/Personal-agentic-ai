package dev.personalagent.personal_assistant

import java.net.URLEncoder
import java.nio.charset.StandardCharsets

internal data class WhatsAppDraftRequest(val number: String, val message: String)

internal object WhatsAppDraftPolicy {
    const val MAX_MESSAGE_LENGTH = 1_600
    private val internationalNumber = Regex("^\\+[1-9][0-9]{6,14}$")

    fun parse(numberValue: Any?, messageValue: Any?): WhatsAppDraftRequest? {
        val number = (numberValue as? String)?.trim() ?: return null
        val message = messageValue as? String ?: return null
        if (!internationalNumber.matches(number) || message.isBlank() || message.length > MAX_MESSAGE_LENGTH) {
            return null
        }
        return WhatsAppDraftRequest(number, message)
    }

    fun link(request: WhatsAppDraftRequest): String {
        val digits = request.number.removePrefix("+")
        val encodedMessage = URLEncoder.encode(request.message, StandardCharsets.UTF_8.name())
            .replace("+", "%20")
        return "https://wa.me/$digits?text=$encodedMessage"
    }
}


internal data class PhoneDialRequest(val number: String)
internal data class SmsDraftRequest(val number: String, val message: String)

internal object PhoneHandoffPolicy {
    const val MAX_SMS_LENGTH = 1_600
    private val internationalNumber = Regex("^\\+[1-9][0-9]{6,14}$")

    fun parseDial(numberValue: Any?): PhoneDialRequest? {
        val number = numberValue as? String ?: return null
        if (!internationalNumber.matches(number)) return null
        return PhoneDialRequest(number)
    }

    fun parseSms(numberValue: Any?, messageValue: Any?): SmsDraftRequest? {
        val number = numberValue as? String ?: return null
        val message = messageValue as? String ?: return null
        if (!internationalNumber.matches(number) || message.isBlank() ||
            message.length > MAX_SMS_LENGTH || message.any { it.code == 0 }) return null
        return SmsDraftRequest(number, message)
    }
}

internal data class TorchCameraCandidate(
    val id: String,
    val hasFlash: Boolean,
    val isBackFacing: Boolean,
)

internal fun chooseTorchCamera(candidates: List<TorchCameraCandidate>): String? =
    candidates.filter(TorchCameraCandidate::hasFlash)
        .sortedByDescending(TorchCameraCandidate::isBackFacing)
        .firstOrNull()?.id
