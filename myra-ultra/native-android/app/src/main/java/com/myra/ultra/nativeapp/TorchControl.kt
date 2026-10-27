package com.myra.ultra.nativeapp

/** UI state reflects only CameraManager confirmations; a request is never treated as success. */
internal data class TorchUiState(
    val confirmedOn: Boolean? = null,
    val pending: Boolean = false,
    val requestedOn: Boolean? = null,
    val message: String = "Tap the control to check flash support and request camera permission.",
)

internal fun torchRequestStarted(state: TorchUiState, turnOn: Boolean): TorchUiState =
    state.copy(pending = true, requestedOn = turnOn, message = if (turnOn) "Requesting flashlight…" else "Requesting flashlight off…")

internal fun torchModeConfirmed(state: TorchUiState, enabled: Boolean): TorchUiState =
    TorchUiState(confirmedOn = enabled, message = if (enabled) "Android confirms the flashlight is on." else "Android confirms the flashlight is off.")

internal fun torchRequestFailed(state: TorchUiState, message: String): TorchUiState =
    state.copy(pending = false, requestedOn = null, message = message)

internal fun torchModeUnavailable(state: TorchUiState): TorchUiState =
    TorchUiState(confirmedOn = null, message = "Android reports the camera flash is unavailable; its state is not confirmed.")
