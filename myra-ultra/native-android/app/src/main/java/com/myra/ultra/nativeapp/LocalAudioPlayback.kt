package com.myra.ultra.nativeapp

enum class LocalAudioPlaybackState {
    EMPTY,
    READY,
    PREPARING,
    PLAYING,
    PAUSED,
    COMPLETED,
    ERROR,
}

fun isSupportedLocalAudioMimeType(mimeType: String?): Boolean =
    mimeType?.trim()?.lowercase(java.util.Locale.ROOT)?.startsWith("audio/") == true

fun LocalAudioPlaybackState.canStartOrResume(): Boolean =
    this == LocalAudioPlaybackState.READY ||
        this == LocalAudioPlaybackState.PAUSED ||
        this == LocalAudioPlaybackState.COMPLETED

fun LocalAudioPlaybackState.canPause(): Boolean = this == LocalAudioPlaybackState.PLAYING

fun LocalAudioPlaybackState.canStop(): Boolean = this != LocalAudioPlaybackState.EMPTY

fun LocalAudioPlaybackState.canSeek(): Boolean =
    this == LocalAudioPlaybackState.PLAYING || this == LocalAudioPlaybackState.PAUSED

fun clampLocalAudioPosition(positionMs: Long, durationMs: Long): Long =
    positionMs.coerceIn(0L, durationMs.coerceAtLeast(0L))

fun formatLocalAudioTime(positionMs: Long): String {
    val totalSeconds = positionMs.coerceAtLeast(0L) / 1_000L
    val seconds = totalSeconds % 60
    val minutes = (totalSeconds / 60) % 60
    val hours = totalSeconds / 3_600
    return if (hours > 0) {
        String.format(java.util.Locale.ROOT, "%d:%02d:%02d", hours, minutes, seconds)
    } else {
        String.format(java.util.Locale.ROOT, "%02d:%02d", totalSeconds / 60, seconds)
    }
}
