package com.myra.ultra.nativeapp

data class LocalAudioQueueEntry(
    val uriKey: String,
    val title: String,
    val mimeType: String,
)

data class LocalAudioQueueUpdate(
    val entries: List<LocalAudioQueueEntry>,
    val addedCount: Int,
    val ignoredCount: Int,
) {
    val isFull: Boolean get() = entries.size >= LocalAudioQueue.MAX_ENTRIES
}

object LocalAudioQueue {
    const val MAX_ENTRIES = 25
    const val MAX_TITLE_CHARS = 160

    /** Add only picker-selected audio URIs, preserving order and never duplicating URI references. */
    fun add(existing: List<LocalAudioQueueEntry>, incoming: List<LocalAudioQueueEntry>): LocalAudioQueueUpdate {
        val result = existing.take(MAX_ENTRIES).toMutableList()
        val keys = result.mapTo(mutableSetOf()) { it.uriKey }
        var added = 0
        var ignored = 0
        for (entry in incoming) {
            val key = entry.uriKey.trim()
            val title = entry.title.trim().take(MAX_TITLE_CHARS)
            if (key.isEmpty() || title.isEmpty() || !isSupportedLocalAudioMimeType(entry.mimeType) || key in keys || result.size >= MAX_ENTRIES) {
                ignored++
                continue
            }
            result += entry.copy(uriKey = key, title = title, mimeType = entry.mimeType.trim().lowercase(java.util.Locale.ROOT))
            keys += key
            added++
        }
        return LocalAudioQueueUpdate(result, added, ignored)
    }

    fun nextIndex(currentIndex: Int, size: Int): Int? =
        if (size <= 0 || currentIndex !in 0 until size || currentIndex == size - 1) null else currentIndex + 1

    fun previousIndex(currentIndex: Int, size: Int): Int? =
        if (size <= 0 || currentIndex !in 0 until size || currentIndex == 0) null else currentIndex - 1
}
