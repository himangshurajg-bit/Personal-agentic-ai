package com.myra.ultra.nativeapp

/** Suppresses microphone uplink while queued Gemini speech is expected to be audible. */
internal class GeminiLiveMicGate(
    private val outputSampleRate: Int = GeminiLiveProtocol.OUTPUT_SAMPLE_RATE,
    private val tailNanos: Long = DEFAULT_TAIL_NANOS,
) {
    private var outputUntilNanos: Long? = null
    private var bargeInEnabled = false

    init {
        require(outputSampleRate > 0)
        require(tailNanos >= 0)
    }

    @Synchronized
    fun queueOutput(pcmByteCount: Int, nowNanos: Long) {
        require(pcmByteCount >= 0 && pcmByteCount % 2 == 0) { "Output must be 16-bit PCM." }
        if (pcmByteCount == 0) return
        val samples = pcmByteCount / 2L
        val durationNanos = samples * NANOS_PER_SECOND / outputSampleRate
        // The prior deadline includes the tail; don't add a fresh tail per chunk.
        val outputEnd = outputUntilNanos?.let { maxOf(nowNanos, it - tailNanos) } ?: nowNanos
        outputUntilNanos = saturatedAdd(saturatedAdd(outputEnd, durationNanos), tailNanos)
    }

    /** Barge-in keeps the playback gate open so the user can interrupt MYRA. */
    @Synchronized
    fun setBargeInEnabled(enabled: Boolean) {
        bargeInEnabled = enabled
    }

    @Synchronized
    fun shouldSendMicrophone(nowNanos: Long): Boolean =
        bargeInEnabled || (outputUntilNanos?.let { nowNanos >= it } ?: true)

    @Synchronized
    fun clear() {
        outputUntilNanos = null
    }

    private fun saturatedAdd(left: Long, right: Long): Long =
        if (right > 0 && left > Long.MAX_VALUE - right) Long.MAX_VALUE else left + right

    private companion object {
        const val NANOS_PER_SECOND = 1_000_000_000L
        const val DEFAULT_TAIL_NANOS = 250_000_000L
    }
}
