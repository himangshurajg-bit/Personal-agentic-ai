package dev.personalagent.personal_assistant

internal data class FixedVibrationRequest(val durationMillis: Long = 80L)

/** No caller-controlled vibration strength, duration, repetition, or pattern. */
internal object FixedVibrationRequestParser {
    fun parse(arguments: Any?): FixedVibrationRequest? = when (arguments) {
        null -> FixedVibrationRequest()
        is Map<*, *> -> if (arguments.isEmpty()) FixedVibrationRequest() else null
        else -> null
    }
}
