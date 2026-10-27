package com.myra.ultra.nativeapp

internal enum class LocalVideoPreviewState {
    EMPTY, PREPARING, READY, PLAYING, PAUSED, COMPLETED, ERROR,
}

internal fun isSupportedLocalVideoMimeType(mimeType: String?): Boolean =
    mimeType?.trim()?.lowercase(java.util.Locale.ROOT)?.startsWith("video/") == true

internal fun LocalVideoPreviewState.canStartOrResume(): Boolean =
    this == LocalVideoPreviewState.READY ||
        this == LocalVideoPreviewState.PAUSED ||
        this == LocalVideoPreviewState.COMPLETED

internal fun LocalVideoPreviewState.canPause(): Boolean = this == LocalVideoPreviewState.PLAYING

internal fun LocalVideoPreviewState.canStop(): Boolean =
    this == LocalVideoPreviewState.PLAYING ||
        this == LocalVideoPreviewState.PAUSED ||
        this == LocalVideoPreviewState.COMPLETED

internal fun LocalVideoPreviewState.canSeek(): Boolean =
    this == LocalVideoPreviewState.PLAYING || this == LocalVideoPreviewState.PAUSED

internal fun clampLocalVideoPosition(positionMs: Long, durationMs: Long): Long =
    positionMs.coerceIn(0L, durationMs.coerceAtLeast(0L))
