package com.myra.ultra.nativeapp

import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.text.ParsePosition
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

internal data class MyraJournalEntry(val id: String, val date: String, val text: String)

/** Pure validation and persistence codec for the on-device journal. */
internal object JournalData {
    private const val HEX = "0123456789abcdef"
    const val MAX_TEXT_LENGTH = 2_000
    const val MAX_ENTRIES = 2_000

    fun currentDate(nowMillis: Long = System.currentTimeMillis()): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(nowMillis))

    fun isValidDate(value: String): Boolean {
        if (!Regex("\\d{4}-\\d{2}-\\d{2}").matches(value)) return false
        return try {
            val format = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply { isLenient = false }
            val position = ParsePosition(0)
            val parsed = format.parse(value, position)
            parsed != null && position.index == value.length && format.format(parsed) == value
        } catch (_: Exception) { false }
    }

    fun create(rawText: String, date: String, id: String = UUID.randomUUID().toString()): MyraJournalEntry? {
        val text = rawText.trim()
        if (text.isEmpty() || text.length > MAX_TEXT_LENGTH || text.none { !it.isWhitespace() }) return null
        if (!isValidDate(date) || id.isBlank() || id.length > 128) return null
        return MyraJournalEntry(id, date, text)
    }

    fun encode(entry: MyraJournalEntry): String =
        "${toHex(entry.id)}|${entry.date}|${toHex(entry.text)}"

    fun decode(row: String): MyraJournalEntry? {
        return try {
            val parts = row.split('|', limit = 3)
            if (parts.size != 3) return null
            val id = fromHex(parts[0]) ?: return null
            create(fromHex(parts[2]) ?: return null, parts[1], id)
        } catch (_: Exception) { null }
    }

    fun newestFirst(entries: Iterable<MyraJournalEntry>): List<MyraJournalEntry> =
        entries.take(MAX_ENTRIES).sortedWith(compareByDescending<MyraJournalEntry> { it.date }.thenByDescending { it.id })

    private fun toHex(value: String): String = buildString {
        value.toByteArray(Charsets.UTF_8).forEach { byte ->
            val unsigned = byte.toInt() and 0xff
            append(HEX[unsigned ushr 4]); append(HEX[unsigned and 0x0f])
        }
    }

    private fun fromHex(value: String): String? {
        return try {
            if (value.length % 2 != 0) return null
            val bytes = ByteArray(value.length / 2)
            for (i in bytes.indices) {
                val high = HEX.indexOf(value[i * 2]); val low = HEX.indexOf(value[i * 2 + 1])
                if (high < 0 || low < 0) return null
                bytes[i] = ((high shl 4) or low).toByte()
            }
            Charsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(bytes)).toString()
        } catch (_: Exception) { null }
    }
}
