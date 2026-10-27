package com.myra.ultra.nativeapp

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GeminiLiveMicGateTest {
    @Test fun microphoneIsOpenInitiallyAndForEmptyOutput() {
        val gate = GeminiLiveMicGate()
        assertTrue(gate.shouldSendMicrophone(0))
        gate.queueOutput(0, 100)
        assertTrue(gate.shouldSendMicrophone(100))
    }

    @Test fun suppressesUplinkForOutputDurationAndShortTail() {
        val gate = GeminiLiveMicGate()
        val start = 1_000_000_000L
        // 24,000 mono 16-bit samples = one second of Live output.
        gate.queueOutput(24_000 * 2, start)
        assertFalse(gate.shouldSendMicrophone(start))
        assertFalse(gate.shouldSendMicrophone(start + 1_249_999_999L))
        assertTrue(gate.shouldSendMicrophone(start + 1_250_000_000L))
    }

    @Test fun consecutiveChunksExtendPlaybackDeadlineWithoutRepeatingTailPerChunk() {
        val gate = GeminiLiveMicGate()
        val start = 5_000_000_000L
        gate.queueOutput(12_000 * 2, start) // 500 ms
        gate.queueOutput(12_000 * 2, start + 100_000_000L) // queued behind prior output
        assertFalse(gate.shouldSendMicrophone(start + 1_249_999_999L))
        assertTrue(gate.shouldSendMicrophone(start + 1_250_000_000L))
    }

    @Test fun laterOutputRestartsTailAndInterruptionClearsGate() {
        val gate = GeminiLiveMicGate()
        gate.queueOutput(24_000 * 2, 10_000_000_000L)
        gate.queueOutput(2_400 * 2, 11_100_000_000L)
        assertFalse(gate.shouldSendMicrophone(11_449_999_999L))
        gate.clear()
        assertTrue(gate.shouldSendMicrophone(11_100_000_000L))
    }

    @Test fun supportsNegativeMonotonicClockOrigins() {
        val gate = GeminiLiveMicGate()
        val start = -2_000_000_000L
        gate.queueOutput(24_000 * 2, start)
        assertFalse(gate.shouldSendMicrophone(start))
        assertTrue(gate.shouldSendMicrophone(start + 1_250_000_000L))
    }

    @Test fun bargeInIsOffByDefaultAndCanBeToggledDuringQueuedPlayback() {
        val gate = GeminiLiveMicGate()
        val start = 2_000_000_000L
        gate.queueOutput(24_000 * 2, start)
        assertFalse(gate.shouldSendMicrophone(start))

        gate.setBargeInEnabled(true)
        assertTrue(gate.shouldSendMicrophone(start))
        assertTrue(gate.shouldSendMicrophone(start + 1_000_000L))

        gate.setBargeInEnabled(false)
        assertFalse(gate.shouldSendMicrophone(start + 1_000_000L))
        assertTrue(gate.shouldSendMicrophone(start + 1_250_000_000L))
    }

    @Test fun bargeInCanBeEnabledAtSessionStart() {
        val gate = GeminiLiveMicGate().apply { setBargeInEnabled(true) }
        gate.queueOutput(24_000 * 2, 0)
        assertTrue(gate.shouldSendMicrophone(0))
    }

    @Test fun rejectsOddBytePcm() {
        try {
            GeminiLiveMicGate().queueOutput(1, 0)
            throw AssertionError("Expected invalid PCM to be rejected")
        } catch (_: IllegalArgumentException) { }
    }
}
