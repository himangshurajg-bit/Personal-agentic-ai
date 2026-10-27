package com.myra.ultra.nativeapp

import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets

/** Strict, bounded importer for MYRA's own Tasks CSV format. Imported reminders are never armed. */
internal object TaskCsvImport {
    const val MAX_BYTES = 1_000_000
    const val MAX_ROWS = 500
    const val MAX_TITLE_CHARS = 250
    private val headers = listOf("Task", "Status", "Due date", "Due time", "Reminder enabled", "Repeat")

    fun readUtf8Bounded(input: InputStream): String? {
        return try {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        var total = 0
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            total += count
            if (total > MAX_BYTES) return null
            output.write(buffer, 0, count)
        }
        StandardCharsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
            .decode(ByteBuffer.wrap(output.toByteArray())).toString()
        } catch (_: Exception) { null }
    }

    fun parse(source: String): TaskCsvImportResult {
        if (source.length > MAX_BYTES) return TaskCsvImportResult(error = "CSV is larger than the 1 MB import limit.")
        val text = source.removePrefix("\uFEFF")
        val rows = parseRows(text) ?: return TaskCsvImportResult(error = "CSV quoting or row structure is invalid.")
        if (rows.isEmpty() || rows.first() != headers) return TaskCsvImportResult(error = "This file doesn’t have MYRA’s Tasks CSV headers.")
        val dataRows = rows.drop(1)
        if (dataRows.size > MAX_ROWS) return TaskCsvImportResult(error = "Import is limited to $MAX_ROWS tasks at a time.")
        val tasks = mutableListOf<MyraTask>()
        var remindersDisabled = 0
        dataRows.forEachIndexed { index, row ->
            if (row.size != headers.size) return TaskCsvImportResult(error = "Row ${index + 2} must contain exactly six columns.")
            val title = row[0]
            if (title.isBlank() || title.length > MAX_TITLE_CHARS) return TaskCsvImportResult(error = "Row ${index + 2} needs a task title up to $MAX_TITLE_CHARS characters.")
            val done = when (row[1]) { "Open" -> false; "Completed" -> true; else -> return TaskCsvImportResult(error = "Row ${index + 2} has an unknown task status.") }
            val dueAt = if (row[2].isBlank() && row[3].isBlank()) null else parseTaskDueAt(row[2], row[3])
                ?: return TaskCsvImportResult(error = "Row ${index + 2} has an invalid due date or time.")
            val reminder = when (row[4]) { "Yes" -> true; "No" -> false; else -> return TaskCsvImportResult(error = "Row ${index + 2} has an invalid reminder value.") }
            val repeat = when (row[5]) { "Never" -> 0; "Daily" -> 1; "Weekly" -> 7; else -> return TaskCsvImportResult(error = "Row ${index + 2} has an unknown repeat setting.") }
            if ((reminder && (dueAt == null || row[3].isBlank())) || (repeat != 0 && !reminder)) {
                return TaskCsvImportResult(error = "Row ${index + 2} has reminder settings without a timed due date.")
            }
            if (reminder) remindersDisabled++
            tasks += MyraTask("csv-$index", title, done, dueAt, reminderEnabled = false, dueHasTime = dueAt != null && row[3].isNotBlank(), repeatEveryDays = 0)
        }
        if (tasks.isEmpty()) return TaskCsvImportResult(error = "This file contains no tasks to import.")
        return TaskCsvImportResult(tasks = tasks, remindersDisabled = remindersDisabled)
    }

    /** RFC-4180-style quoted fields, doubled quotes, commas, CRLF and embedded line breaks. */
    private fun parseRows(text: String): List<List<String>>? {
        val rows = mutableListOf<List<String>>()
        val cells = mutableListOf<String>()
        val field = StringBuilder()
        var inQuotes = false
        var afterQuote = false
        var atFieldStart = true
        var i = 0
        fun finishField() {
            cells += field.toString()
            field.setLength(0)
            atFieldStart = true
            afterQuote = false
        }
        fun finishRow() {
            finishField()
            if (cells.any { it.isNotEmpty() }) rows += cells.toList()
            cells.clear()
        }
        while (i < text.length) {
            val ch = text[i]
            if (inQuotes) {
                if (ch == '"') {
                    if (i + 1 < text.length && text[i + 1] == '"') { field.append('"'); i++ }
                    else { inQuotes = false; afterQuote = true }
                } else field.append(ch)
            } else if (afterQuote) {
                when (ch) {
                    ',' -> finishField()
                    '\r', '\n' -> { finishRow(); if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++ }
                    else -> return null
                }
            } else {
                when (ch) {
                    '"' -> if (atFieldStart) { inQuotes = true; atFieldStart = false } else return null
                    ',' -> finishField()
                    '\r', '\n' -> { finishRow(); if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++ }
                    else -> { field.append(ch); atFieldStart = false }
                }
            }
            i++
            if (rows.size > MAX_ROWS + 2) return null
        }
        if (inQuotes) return null
        if (cells.isNotEmpty() || field.isNotEmpty() || afterQuote) finishRow()
        return rows
    }
}

internal data class TaskCsvImportResult(
    val tasks: List<MyraTask> = emptyList(),
    val remindersDisabled: Int = 0,
    val error: String? = null,
)
