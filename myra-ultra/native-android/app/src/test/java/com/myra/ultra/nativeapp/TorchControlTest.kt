package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TorchControlTest {
    @Test fun startingRequestDoesNotClaimHardwareChanged() {
        val state = torchRequestStarted(TorchUiState(confirmedOn = false), true)
        assertFalse(state.confirmedOn!!)
        assertTrue(state.pending)
        assertEquals(true, state.requestedOn)
        assertEquals("Requesting flashlight…", state.message)
    }

    @Test fun platformCallbackIsTheOnlyPathThatConfirmsOnOrOff() {
        val requested = torchRequestStarted(TorchUiState(), true)
        val on = torchModeConfirmed(requested, true)
        assertEquals(true, on.confirmedOn)
        assertFalse(on.pending)
        val offRequest = torchRequestStarted(on, false)
        assertEquals(true, offRequest.confirmedOn)
        val off = torchModeConfirmed(offRequest, false)
        assertEquals(false, off.confirmedOn)
        assertFalse(off.pending)
    }

    @Test fun failedRequestPreservesLastConfirmedStateWithoutClaimingSuccess() {
        val state = torchRequestStarted(TorchUiState(confirmedOn = true), false)
        val failed = torchRequestFailed(state, "Android could not change the flashlight.")
        assertEquals(true, failed.confirmedOn)
        assertFalse(failed.pending)
        assertNull(failed.requestedOn)
        assertEquals("Android could not change the flashlight.", failed.message)
    }

    @Test fun unavailableFlashClearsConfirmationAndReportsUnknownState() {
        val unavailable = torchModeUnavailable(torchRequestStarted(TorchUiState(confirmedOn = true), false))
        assertNull(unavailable.confirmedOn)
        assertFalse(unavailable.pending)
        assertTrue(unavailable.message.contains("not confirmed"))
    }
}
