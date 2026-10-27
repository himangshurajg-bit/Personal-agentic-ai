package dev.personalagent.personal_assistant

import java.util.Locale

data class LocalAudioQueueEntry(
    val uriKey: String,
    val title: String,
    val mimeType: String,
)

data class LocalAudioQueueUpdate(
    val entries: List<LocalAudioQueueEntry>,
    val addedCount: Int,
    val ignoredCount: Int,
)

/** Bounded rules for the temporary, picker-selected local audio queue. */
object LocalAudioQueue {
    const val MAX_ENTRIES = 25
    const val MAX_TITLE_CHARS = 160

    fun add(
        existing: List<LocalAudioQueueEntry>,
        incoming: List<LocalAudioQueueEntry>,
    ): LocalAudioQueueUpdate {
        val result = mutableListOf<LocalAudioQueueEntry>()
        val keys = mutableSetOf<String>()
        var ignored = 0
        for (entry in existing) {
            val key = entry.uriKey.trim()
            val title = entry.title.trim().take(MAX_TITLE_CHARS)
            val mime = entry.mimeType.trim().lowercase(Locale.ROOT)
            if (key.isEmpty() || title.isEmpty() || !mime.startsWith("audio/") || key in keys || result.size >= MAX_ENTRIES) {
                ignored++
                continue
            }
            result += entry.copy(uriKey = key, title = title, mimeType = mime)
            keys += key
        }
        val existingCount = result.size
        for (entry in incoming) {
            val key = entry.uriKey.trim()
            val title = entry.title.trim().take(MAX_TITLE_CHARS)
            val mime = entry.mimeType.trim().lowercase(Locale.ROOT)
            if (key.isEmpty() || title.isEmpty() || !mime.startsWith("audio/") || key in keys || result.size >= MAX_ENTRIES) {
                ignored++
                continue
            }
            result += entry.copy(uriKey = key, title = title, mimeType = mime)
            keys += key
        }
        return LocalAudioQueueUpdate(
            entries = result,
            addedCount = result.size - existingCount,
            ignoredCount = ignored,
        )
    }

    fun nextIndex(currentIndex: Int, size: Int): Int? =
        if (size <= 0 || currentIndex !in 0 until size || currentIndex == size - 1) null else currentIndex + 1

    fun previousIndex(currentIndex: Int, size: Int): Int? =
        if (size <= 0 || currentIndex !in 0 until size || currentIndex == 0) null else currentIndex - 1

    fun clampPosition(positionMs: Long, durationMs: Long): Long =
        positionMs.coerceIn(0L, durationMs.coerceAtLeast(0L))
}

enum class LocalAudioPlaybackState {
    EMPTY, READY, PREPARING, PLAYING, PAUSED, COMPLETED, ERROR,
}

fun LocalAudioPlaybackState.canStartOrResume(): Boolean =
    this == LocalAudioPlaybackState.READY ||
        this == LocalAudioPlaybackState.PAUSED ||
        this == LocalAudioPlaybackState.COMPLETED

fun LocalAudioPlaybackState.canPause(): Boolean = this == LocalAudioPlaybackState.PLAYING
fun LocalAudioPlaybackState.canStop(): Boolean = this != LocalAudioPlaybackState.EMPTY
