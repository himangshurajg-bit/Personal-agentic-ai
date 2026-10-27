package com.myra.ultra.nativeapp

import java.math.BigDecimal
import java.math.RoundingMode
import java.text.ParsePosition
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

internal data class MyraExpense(
    val id: String,
    val amountMinor: Long,
    val category: String,
    val note: String,
    val date: String,
)

internal object ExpenseData {
    private const val HEX = "0123456789abcdef"
    private const val MAX_MINOR_UNITS = 9_999_999_999_999L

    fun amountToMinorUnits(raw: String): Long? {
        return try {
            val value = BigDecimal(raw.trim())
            if (value <= BigDecimal.ZERO || value.scale() > 2) return null
            value.setScale(2, RoundingMode.UNNECESSARY).movePointRight(2).longValueExact()
                .takeIf { it in 1..MAX_MINOR_UNITS }
        } catch (_: Exception) { null }
    }

    fun isValidDate(raw: String): Boolean {
        val input = raw.trim()
        return try {
            val format = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply { isLenient = false }
            val position = ParsePosition(0)
            val parsed = format.parse(input, position)
            parsed != null && position.index == input.length && format.format(parsed) == input
        } catch (_: Exception) { false }
    }

    fun currentDate(): String = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
    fun currentMonth(): String = SimpleDateFormat("yyyy-MM", Locale.US).format(Date())

    fun formatAmount(amountMinor: Long): String = BigDecimal.valueOf(amountMinor, 2).toPlainString()

    fun monthTotal(expenses: Iterable<MyraExpense>, yearMonth: String): Long =
        expenses.asSequence().filter { it.date.startsWith("$yearMonth-") }.sumOf { it.amountMinor }

    fun encode(expense: MyraExpense): String = listOf(
        expense.id,
        expense.amountMinor.toString(),
        hex(expense.category),
        hex(expense.note),
        expense.date,
    ).joinToString("|")

    fun decode(row: String): MyraExpense? {
        return try {
            val parts = row.split('|', limit = 5)
            val amount = parts.getOrNull(1)?.toLongOrNull()
            if (parts.size != 5 || parts[0].isBlank() || amount == null || amount !in 1..MAX_MINOR_UNITS || !isValidDate(parts[4])) return null
            val category = unhex(parts[2]) ?: return null
            val note = unhex(parts[3]) ?: return null
            if (category.isBlank() || category.length > 32 || note.length > 160) return null
            MyraExpense(parts[0], amount, category, note, parts[4])
        } catch (_: Exception) { null }
    }

    private fun hex(value: String): String = buildString {
        value.toByteArray(Charsets.UTF_8).forEach { byte ->
            val unsigned = byte.toInt() and 0xff
            append(HEX[unsigned ushr 4]); append(HEX[unsigned and 0x0f])
        }
    }

    private fun unhex(value: String): String? {
        return try {
            if (value.length % 2 != 0) return null
            val bytes = ByteArray(value.length / 2)
            for (i in bytes.indices) {
                val hi = HEX.indexOf(value[i * 2]); val lo = HEX.indexOf(value[i * 2 + 1])
                if (hi < 0 || lo < 0) return null
                bytes[i] = ((hi shl 4) or lo).toByte()
            }
            Charsets.UTF_8.newDecoder()
                .onMalformedInput(java.nio.charset.CodingErrorAction.REPORT)
                .onUnmappableCharacter(java.nio.charset.CodingErrorAction.REPORT)
                .decode(java.nio.ByteBuffer.wrap(bytes)).toString()
        } catch (_: Exception) { null }
    }
}
