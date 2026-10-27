package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Test

class CsvExportTest {
    @Test fun expenseCsvHasStableColumnsAndEscapesText() {
        val csv = CsvExport.expenses(listOf(MyraExpense("1", 1250, "Food, drink", "tea \"and\" snacks", "2026-10-23")))
        assertEquals("Date,Category,Amount,Note\r\n2026-10-23,\"Food, drink\",12.50,\"tea \"\"and\"\" snacks\"\r\n", csv)
    }

    @Test fun taskCsvExportsStatusDueAndReminderWithoutSpreadsheetFormulas() {
        val due = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm", java.util.Locale.US)
            .parse("2026-10-29 09:30")!!.time
        val csv = CsvExport.tasks(listOf(
            MyraTask("1", "=Study, physics", false, due, true, true, 7),
            MyraTask("2", "Read \"notes\"", true),
        ))
        assertEquals(
            "Task,Status,Due date,Due time,Reminder enabled,Repeat\r\n" +
                "\"'=Study, physics\",Open,2026-10-29,09:30,Yes,Weekly\r\n" +
                "\"Read \"\"notes\"\"\",Completed,,,No,Never\r\n",
            csv,
        )
    }

    @Test fun taskCsvEmptyListStillHasPortableHeaders() {
        assertEquals("Task,Status,Due date,Due time,Reminder enabled,Repeat\r\n", CsvExport.tasks(emptyList()))
    }

    @Test fun journalCsvQuotesNewlinesAndProtectsFormulaLikeText() {
        val csv = CsvExport.journal(listOf(MyraJournalEntry("1", "2026-10-23", "=1+1\nnot a formula")))
        assertEquals("Date,Entry\r\n2026-10-23,\"'=1+1\nnot a formula\"\r\n", csv)
    }

    @Test fun waterAndHabitExportsIncludeDatesAndProtectSpreadsheetFormulas() {
        val water = CsvExport.water(listOf(WaterEntry("w", "2026-10-23", 500)))
        assertEquals("Date,Milliliters\r\n2026-10-23,500\r\n", water)
        val habit = MyraHabit("h", "=Run", setOf("2026-10-22", "2026-10-23"))
        assertEquals("Habit,Completed dates,Current streak\r\n'=Run,2026-10-22; 2026-10-23,2\r\n", CsvExport.habits(listOf(habit), "2026-10-23"))
    }

    @Test fun localActivityExportUsesUtcTimestampsProtectsTextAndKeepsNewestEventsFirst() {
        val csv = CsvExport.activity(listOf(
            LocalActivityEvent("old", 0L, "=Start", "line, one\nline two"),
            LocalActivityEvent("new", 1_000L, "Task \"done\"", "completed"),
        ))
        assertEquals(
            "Timestamp (UTC),Action,Details\r\n" +
                "1970-01-01T00:00:01.000Z,\"Task \"\"done\"\"\",completed\r\n" +
                "1970-01-01T00:00:00.000Z,'=Start,\"line, one\nline two\"\r\n",
            csv,
        )
    }

    @Test fun activityExportIncludesHeadersWhenFeedIsEmpty() {
        assertEquals("Timestamp (UTC),Action,Details\r\n", CsvExport.activity(emptyList()))
    }

    @Test fun exportsEmptyFilesWithHeadersAndPreservesUnicode() {
        assertEquals("Date,Category,Amount,Note\r\n", CsvExport.expenses(emptyList()))
        assertEquals("Date,Entry\r\n2026-10-23,こんにちは 🌱\r\n", CsvExport.journal(listOf(MyraJournalEntry("1", "2026-10-23", "こんにちは 🌱"))))
    }
}
