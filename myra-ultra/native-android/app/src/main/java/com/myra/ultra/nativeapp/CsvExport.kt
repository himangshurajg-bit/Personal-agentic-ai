package com.myra.ultra.nativeapp

/** Builds spreadsheet-safe CSV exports without changing the device-local source records. */
internal object CsvExport {
    fun expenses(rows: Iterable<MyraExpense>): String = csv(
        listOf("Date", "Category", "Amount", "Note"),
        rows.map { listOf(it.date, it.category, ExpenseData.formatAmount(it.amountMinor), it.note) },
    )

    fun tasks(rows: Iterable<MyraTask>): String {
        val dateFormat = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US)
        val timeFormat = java.text.SimpleDateFormat("HH:mm", java.util.Locale.US)
        return csv(
            listOf("Task", "Status", "Due date", "Due time", "Reminder enabled", "Repeat"),
            rows.map { task ->
                val due = task.dueAtMillis?.let { java.util.Date(it) }
                val repeat = when (task.repeatEveryDays) { 1 -> "Daily"; 7 -> "Weekly"; else -> "Never" }
                listOf(
                    task.title,
                    if (task.done) "Completed" else "Open",
                    if (due != null) dateFormat.format(due) else "",
                    if (due != null && task.dueHasTime) timeFormat.format(due) else "",
                    if (task.reminderEnabled) "Yes" else "No",
                    repeat,
                )
            },
        )
    }

    fun journal(rows: Iterable<MyraJournalEntry>): String = csv(
        listOf("Date", "Entry"),
        rows.map { listOf(it.date, it.text) },
    )

    fun water(rows: Iterable<WaterEntry>): String = csv(
        listOf("Date", "Milliliters"),
        rows.map { listOf(it.date, it.milliliters.toString()) },
    )

    fun habits(rows: Iterable<MyraHabit>, today: String): String = csv(
        listOf("Habit", "Completed dates", "Current streak"),
        rows.map { habit -> listOf(habit.title, habit.completedDates.sorted().joinToString("; "), HabitTracker.currentStreak(habit, today).toString()) },
    )

    fun activity(events: Iterable<LocalActivityEvent>): String {
        val timestampFormat = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", java.util.Locale.US).apply {
            timeZone = java.util.TimeZone.getTimeZone("UTC")
        }
        return csv(
            listOf("Timestamp (UTC)", "Action", "Details"),
            events.sortedByDescending { it.timestampMillis }
                .take(LocalActivityFeed.MAX_EVENTS)
                .map { event -> listOf(timestampFormat.format(java.util.Date(event.timestampMillis)), event.label, event.detail) },
        )
    }

    private fun csv(headers: List<String>, rows: Iterable<List<String>>): String = buildString {
        append(headers.joinToString(",", transform = ::field)).append("\r\n")
        rows.forEach { row ->
            append(row.joinToString(",", transform = ::field)).append("\r\n")
        }
    }

    private fun field(value: String): String {
        // Prevent spreadsheet programs from evaluating user-entered text as a formula.
        val firstMeaningful = value.dropWhile { it.isWhitespace() }.firstOrNull()
        val safe = if (firstMeaningful in setOf('=', '+', '-', '@')) "'$value" else value
        return if (safe.any { it == ',' || it == '"' || it == '\r' || it == '\n' }) {
            "\"${safe.replace("\"", "\"\"")}\""
        } else safe
    }
}

internal fun writeCsvExport(context: android.content.Context, uri: android.net.Uri, csv: String): Boolean = try {
    context.contentResolver.openOutputStream(uri, "wt")?.use { stream ->
        stream.write(csv.toByteArray(Charsets.UTF_8))
        stream.flush()
    } != null
} catch (_: Exception) {
    false
}
