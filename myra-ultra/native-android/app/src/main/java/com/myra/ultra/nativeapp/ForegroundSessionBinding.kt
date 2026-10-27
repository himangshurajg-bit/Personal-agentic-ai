package com.myra.ultra.nativeapp

/** Keeps lifecycle callbacks attached to the latest session rather than a stale composition value. */
internal class ForegroundSessionBinding<T : Any>(private val close: (T) -> Unit) {
    private val lock = Any()
    private var current: T? = null

    fun bind(session: T?) {
        synchronized(lock) { current = session }
    }

    /** Detaches only the session that ended, so a late callback cannot clear its successor. */
    fun clearIfCurrent(session: T): Boolean = synchronized(lock) {
        if (current !== session) return@synchronized false
        current = null
        true
    }

    /** Atomically detaches then closes the active session; repeated lifecycle callbacks are safe. */
    fun closeCurrent() {
        val session = synchronized(lock) {
            current.also { current = null }
        }
        session?.let(close)
    }
}
