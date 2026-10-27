package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class GeminiLiveResumptionTest {
    @Test fun onlyEligibleNonEmptyBoundedHandlesReplaceTheCurrentHandle() {
        val state = GeminiLiveResumptionState()
        state.update(true, "first")
        state.update(false, "must-not-replace")
        state.update(true, "")
        state.update(true, "  ")
        state.update(true, "bad\nhandle")
        state.update(true, "h".repeat(GeminiLiveProtocol.MAX_SESSION_HANDLE_CHARS + 1))
        assertEquals("first", state.handleForSetup(0L))

        state.update(true, "latest")
        assertEquals("latest", state.handleForSetup(0L))
    }

    @Test fun handleExpiresAtMostTwoHoursAfterSessionTermination() {
        val state = GeminiLiveResumptionState()
        state.update(true, "opaque")
        val endedAt = 1_000L
        state.markSessionEnded(endedAt)
        assertEquals("opaque", state.handleForSetup(endedAt + GeminiLiveResumptionState.MAX_RETENTION_MILLIS - 1))
        assertNull(state.handleForSetup(endedAt + GeminiLiveResumptionState.MAX_RETENTION_MILLIS))
    }

    @Test fun resumedSessionRestartsRetentionFromItsNextTerminationAndStopClearsHandle() {
        val state = GeminiLiveResumptionState()
        state.update(true, "old")
        state.markSessionEnded(10L)
        state.markSessionActive()
        assertEquals("old", state.handleForSetup(10L + GeminiLiveResumptionState.MAX_RETENTION_MILLIS + 1))
        state.markSessionEnded(20L)
        state.update(true, "new")
        state.markSessionEnded(30L)
        assertEquals("new", state.handleForSetup(30L + GeminiLiveResumptionState.MAX_RETENTION_MILLIS - 1))
        assertNull(state.handleForSetup(30L + GeminiLiveResumptionState.MAX_RETENTION_MILLIS))
        state.update(true, "stop-me")
        state.clear()
        assertNull(state.handleForSetup(40L))
    }

    @Test fun reconnectAndGoAwayDelaysAreBounded() {
        assertEquals(1_000L, GeminiLiveResumptionState.retryDelayMillis(1))
        assertEquals(2_000L, GeminiLiveResumptionState.retryDelayMillis(2))
        assertEquals(0L, GeminiLiveResumptionState.retryDelayMillis(3))
        assertEquals(0L, GeminiLiveResumptionState.goAwayDelayMillis(0L))
        assertEquals(0L, GeminiLiveResumptionState.goAwayDelayMillis(999L))
        assertEquals(9_000L, GeminiLiveResumptionState.goAwayDelayMillis(10_000L))
        assertEquals(119_000L, GeminiLiveResumptionState.goAwayDelayMillis(Long.MAX_VALUE))
    }

    @Test fun configuredRetentionCannotExceedProviderWindow() {
        val state = GeminiLiveResumptionState(Long.MAX_VALUE)
        state.update(true, "bounded")
        state.markSessionEnded(0L)
        assertEquals("bounded", state.handleForSetup(GeminiLiveResumptionState.MAX_RETENTION_MILLIS - 1))
        assertNull(state.handleForSetup(GeminiLiveResumptionState.MAX_RETENTION_MILLIS))
    }
}
