package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ForegroundSessionBindingTest {
    @Test fun foregroundStopClosesTheMostRecentlyBoundSessionOnce() {
        val closed = mutableListOf<String>()
        val binding = ForegroundSessionBinding<String>(closed::add)
        binding.bind("live-session")

        binding.closeCurrent()
        binding.closeCurrent()

        assertEquals(listOf("live-session"), closed)
    }

    @Test fun lateEndCallbackFromOldSessionCannotClearOrCloseItsSuccessor() {
        val closed = mutableListOf<String>()
        val binding = ForegroundSessionBinding<String>(closed::add)
        binding.bind("old")
        binding.bind("new")

        assertFalse(binding.clearIfCurrent("old"))
        binding.closeCurrent()

        assertEquals(listOf("new"), closed)
    }

    @Test fun currentEndCallbackDetachesSessionBeforeLifecycleCleanup() {
        val closed = mutableListOf<String>()
        val binding = ForegroundSessionBinding<String>(closed::add)
        binding.bind("ended")

        assertTrue(binding.clearIfCurrent("ended"))
        binding.closeCurrent()

        assertEquals(emptyList<String>(), closed)
    }
}
