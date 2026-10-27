package com.myra.ultra.nativeapp

/** Holds only the latest eligible Live resumption handle, in memory, for at most two hours. */
internal class GeminiLiveResumptionState(
    private val retentionMillis: Long = MAX_RETENTION_MILLIS,
) {
    private var handle: String? = null
    private var expiresAtElapsedMillis: Long? = null

    @Synchronized
    fun update(resumable: Boolean, newHandle: String?) {
        // A handle is replaced only by a valid, non-empty resumable update.
        if (!resumable || newHandle.isNullOrBlank() || newHandle.length > GeminiLiveProtocol.MAX_SESSION_HANDLE_CHARS || newHandle.any(Char::isISOControl)) return
        handle = newHandle
        expiresAtElapsedMillis = null
    }

    @Synchronized
    fun handleForSetup(nowElapsedMillis: Long): String? {
        val expiry = expiresAtElapsedMillis
        if (expiry != null && nowElapsedMillis >= expiry) clear()
        return handle
    }

    @Synchronized
    fun markSessionEnded(nowElapsedMillis: Long) {
        if (handle != null && expiresAtElapsedMillis == null) {
            // Clamp even internal callers so no configuration can extend retention past Google's limit.
            expiresAtElapsedMillis = safeAdd(nowElapsedMillis, retentionMillis.coerceIn(0L, MAX_RETENTION_MILLIS))
        }
    }

    @Synchronized
    fun markSessionActive() {
        expiresAtElapsedMillis = null
    }

    @Synchronized
    fun clear() {
        handle = null
        expiresAtElapsedMillis = null
    }

    private fun safeAdd(left: Long, right: Long): Long =
        if (right > 0 && left > Long.MAX_VALUE - right) Long.MAX_VALUE else left + right

    companion object {
        const val MAX_RETENTION_MILLIS = 2 * 60 * 60 * 1000L
        const val MAX_RECONNECT_ATTEMPTS = 2

        /** A small bounded backoff; never use an untrusted server-provided delay directly. */
        fun retryDelayMillis(attempt: Int): Long = when (attempt) {
            1 -> 1_000L
            2 -> 2_000L
            else -> 0L
        }

        /** Start shortly before the server's GoAway deadline, with a hard maximum delay. */
        fun goAwayDelayMillis(timeLeftMillis: Long): Long = (timeLeftMillis.coerceIn(0L, 120_000L) - 1_000L).coerceAtLeast(0L)
    }
}
