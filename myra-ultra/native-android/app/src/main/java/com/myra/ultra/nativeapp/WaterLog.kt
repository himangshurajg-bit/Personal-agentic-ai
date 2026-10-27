package com.myra.ultra.nativeapp

import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

internal data class WaterEntry(val id: String, val date: String, val milliliters: Int)

internal object WaterLog {
    private const val HEX = "0123456789abcdef"
    private val datePattern = Regex("\\d{4}-\\d{2}-\\d{2}")

    fun currentDate(nowMillis: Long = System.currentTimeMillis()): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(nowMillis))

    fun parseMilliliters(input: String): Int? = input.trim().toIntOrNull()?.takeIf { it in 1..4000 }

    fun isValidDate(value: String): Boolean {
        if (!datePattern.matches(value)) return false
        return try {
            SimpleDateFormat("yyyy-MM-dd", Locale.US).apply { isLenient = false }.parse(value) != null
        } catch (_: Exception) { false }
    }

    fun newEntry(date: String, milliliters: Int, id: String = UUID.randomUUID().toString()): WaterEntry? =
        if (id.isBlank() || !isValidDate(date) || milliliters !in 1..4000) null
        else WaterEntry(id, date, milliliters)

    fun totalForDate(entries: Iterable<WaterEntry>, date: String): Long =
        entries.asSequence().filter { it.date == date }.sumOf { it.milliliters.toLong() }

    fun encode(entry: WaterEntry): String = "${toHex(entry.id)}|${entry.date}|${entry.milliliters}"

    fun decode(row: String): WaterEntry? {
        return try {
            val parts = row.split('|', limit = 3)
            if (parts.size != 3) return null
            val idBytes = fromHex(parts[0]) ?: return null
            val id = Charsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(idBytes)).toString()
            newEntry(parts[1], parts[2].toIntOrNull() ?: return null, id)
        } catch (_: Exception) { null }
    }

    private fun toHex(value: String): String = buildString {
        value.toByteArray(Charsets.UTF_8).forEach { byte ->
            val valueByte = byte.toInt() and 0xff
            append(HEX[valueByte ushr 4]); append(HEX[valueByte and 0x0f])
        }
    }

    private fun fromHex(value: String): ByteArray? {
        if (value.length % 2 != 0) return null
        val bytes = ByteArray(value.length / 2)
        for (i in bytes.indices) {
            val high = HEX.indexOf(value[i * 2])
            val low = HEX.indexOf(value[i * 2 + 1])
            if (high < 0 || low < 0) return null
            bytes[i] = ((high shl 4) or low).toByte()
        }
        return bytes
    }
}
