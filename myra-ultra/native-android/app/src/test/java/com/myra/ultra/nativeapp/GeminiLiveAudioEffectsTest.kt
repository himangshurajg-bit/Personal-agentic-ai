package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GeminiLiveAudioEffectsTest {
    private class FakeHandle(
        private val enableResult: Boolean = true,
        private val enabledResult: Boolean = true,
        private val releaseFailure: Boolean = false,
    ) : GeminiLiveAudioEffects.Handle {
        var released = 0
        override fun enable() = enableResult
        override fun isEnabled() = enabledResult
        override fun release() {
            released++
            if (releaseFailure) error("release failed")
        }
    }

    private class FakeFactory(
        private val unavailable: Set<GeminiLiveAudioEffects.Kind> = emptySet(),
        private val handles: Map<GeminiLiveAudioEffects.Kind, FakeHandle> = emptyMap(),
        private val createFailures: Set<GeminiLiveAudioEffects.Kind> = emptySet(),
    ) : GeminiLiveAudioEffects.Factory {
        val checked = mutableListOf<GeminiLiveAudioEffects.Kind>()
        val created = mutableListOf<GeminiLiveAudioEffects.Kind>()
        val sessionIds = mutableListOf<Int>()

        override fun isAvailable(kind: GeminiLiveAudioEffects.Kind): Boolean {
            checked += kind
            return kind !in unavailable
        }

        override fun create(kind: GeminiLiveAudioEffects.Kind, audioSessionId: Int): GeminiLiveAudioEffects.Handle? {
            created += kind
            sessionIds += audioSessionId
            if (kind in createFailures) error("creation failed")
            return handles[kind]
        }
    }

    @Test fun requestsAllThreePrototypeAudioEffectsForTheActiveCaptureSession() {
        val kinds = GeminiLiveAudioEffects.Kind.values().toList()
        val handles = kinds.associateWith { FakeHandle() }
        val factory = FakeFactory(handles = handles)

        val active = GeminiLiveAudioEffects.attach(42, factory)

        assertEquals(kinds, factory.checked)
        assertEquals(kinds, factory.created)
        assertEquals(listOf(42, 42, 42), factory.sessionIds)
        assertEquals(kinds.map { it.label }, active.enabledLabels)
        active.close()
        assertTrue(handles.values.all { it.released == 1 })
    }

    @Test fun unavailableOrUncreatableEffectsDoNotBlockTheRemainingEffects() {
        val echo = FakeHandle()
        val gain = FakeHandle()
        val factory = FakeFactory(
            unavailable = setOf(GeminiLiveAudioEffects.Kind.ECHO_CANCELLATION),
            handles = mapOf(
                GeminiLiveAudioEffects.Kind.NOISE_SUPPRESSION to echo,
                GeminiLiveAudioEffects.Kind.AUTOMATIC_GAIN_CONTROL to gain,
            ),
            createFailures = setOf(GeminiLiveAudioEffects.Kind.AUTOMATIC_GAIN_CONTROL),
        )

        val active = GeminiLiveAudioEffects.attach(7, factory)

        assertEquals(listOf("noise suppression"), active.enabledLabels)
        assertEquals(listOf(GeminiLiveAudioEffects.Kind.NOISE_SUPPRESSION, GeminiLiveAudioEffects.Kind.AUTOMATIC_GAIN_CONTROL), factory.created)
        active.close()
        assertEquals(1, echo.released)
        assertEquals(0, gain.released)
    }

    @Test fun disabledEffectIsReleasedAndNotReportedAsEnabled() {
        val disabled = FakeHandle(enableResult = true, enabledResult = false)
        val active = GeminiLiveAudioEffects.attach(
            9,
            FakeFactory(handles = mapOf(GeminiLiveAudioEffects.Kind.ECHO_CANCELLATION to disabled)),
        )

        assertTrue(active.enabledLabels.isEmpty())
        assertEquals(1, disabled.released)
        active.close()
        assertEquals(1, disabled.released)
    }

    @Test fun closeIsIdempotentAndCleanupFailureDoesNotEscape() {
        val handle = FakeHandle(releaseFailure = true)
        val active = GeminiLiveAudioEffects.attach(
            11,
            FakeFactory(handles = mapOf(GeminiLiveAudioEffects.Kind.NOISE_SUPPRESSION to handle)),
        )

        active.close()
        active.close()

        assertEquals(1, handle.released)
        assertFalse(active.enabledLabels.isEmpty())
    }
}
