package com.myra.ultra.nativeapp

import java.util.Base64
import java.util.UUID

data class LocalActivityEvent(
    val id: String,
    val timestampMillis: Long,
    val label: String,
    val detail: String,
)

/** A small, on-device journal of explicit actions taken in MYRA's local workspace. */
object LocalActivityFeed {
    const val MAX_EVENTS = 100
    const val MAX_LABEL_CHARS = 48
    const val MAX_DETAIL_CHARS = 120

    fun record(
        existing: List<LocalActivityEvent>,
        label: String,
        detail: String,
        timestampMillis: Long,
        id: String = UUID.randomUUID().toString(),
    ): List<LocalActivityEvent>? {
        val cleanLabel = label.trim()
        val cleanDetail = detail.trim()
        if (id.isBlank() || timestampMillis < 0L || cleanLabel.isEmpty() || cleanLabel.length > MAX_LABEL_CHARS ||
            cleanDetail.isEmpty() || cleanDetail.length > MAX_DETAIL_CHARS || existing.any { it.id == id }) return null
        return (existing + LocalActivityEvent(id, timestampMillis, cleanLabel, cleanDetail))
            .sortedWith(compareByDescending<LocalActivityEvent> { it.timestampMillis }.thenByDescending { it.id })
            .take(MAX_EVENTS)
    }

    fun encode(events: List<LocalActivityEvent>): String = events
        .sortedWith(compareByDescending<LocalActivityEvent> { it.timestampMillis }.thenByDescending { it.id })
        .take(MAX_EVENTS)
        .joinToString("\n") { event ->
            "${text(event.id)}|${event.timestampMillis}|${text(event.label)}|${text(event.detail)}"
        }

    fun decode(serialized: String): List<LocalActivityEvent> = serialized.lineSequence().mapNotNull { row ->
        try {
            val fields = row.split('|', limit = 4)
            if (fields.size != 4) return@mapNotNull null
            val id = untext(fields[0])
            val timestamp = fields[1].toLongOrNull() ?: return@mapNotNull null
            val label = untext(fields[2])
            val detail = untext(fields[3])
            if (id.isBlank() || timestamp < 0L || label.isBlank() || label.length > MAX_LABEL_CHARS ||
                detail.isBlank() || detail.length > MAX_DETAIL_CHARS) return@mapNotNull null
            LocalActivityEvent(id, timestamp, label, detail)
        } catch (_: Exception) { null }
    }.distinctBy { it.id }
        .sortedWith(compareByDescending<LocalActivityEvent> { it.timestampMillis }.thenByDescending { it.id })
        .take(MAX_EVENTS)
        .toList()

    private fun text(value: String): String = Base64.getUrlEncoder().withoutPadding().encodeToString(value.toByteArray(Charsets.UTF_8))
    private fun untext(value: String): String = String(Base64.getUrlDecoder().decode(value), Charsets.UTF_8)
}
