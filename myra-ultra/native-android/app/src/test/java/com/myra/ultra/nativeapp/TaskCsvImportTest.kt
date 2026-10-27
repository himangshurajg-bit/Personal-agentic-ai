package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayInputStream
import java.nio.charset.StandardCharsets
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

class TaskCsvImportTest {
    @Test fun importsExportedRowsWithQuotedTextAndLeavesReminderSchedulingOff() {
        val due = parseTaskDueAt("2026-10-29", "09:30", TimeZone.getTimeZone("UTC"))!!
        val source = CsvExport.tasks(listOf(
            MyraTask("old1", "Read, then \"review\"\nnotes", false, due, true, true, 7),
            MyraTask("old2", "Finished", true),
            MyraTask("old3", "=unsafe", false),
        ))
        val result = TaskCsvImport.parse(source)
        assertNull(result.error)
        assertEquals(3, result.tasks.size)
        assertEquals("Read, then \"review\"\nnotes", result.tasks[0].title)
        assertEquals("2026-10-29 09:30", SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") }.format(Date(result.tasks[0].dueAtMillis!!)))
        assertFalse(result.tasks[0].done)
        assertTrue(result.tasks[1].done)
        assertEquals("'=unsafe", result.tasks[2].title)
        assertEquals(1, result.remindersDisabled)
        assertTrue(result.tasks.all { !it.reminderEnabled && it.repeatEveryDays == 0 })
    }

    @Test fun acceptsBomAndCrLfAndDateWithoutTime() {
        val input = "\uFEFFTask,Status,Due date,Due time,Reminder enabled,Repeat\r\nStudy,Open,2026-10-29,,No,Never\r\n"
        val result = TaskCsvImport.parse(input)
        assertNull(result.error)
        assertEquals(1, result.tasks.size)
        assertFalse(result.tasks.single().dueHasTime)
    }

    @Test fun rejectsUnknownHeadersMalformedRowsAndBadQuotingAsWholeFile() {
        assertTrue(TaskCsvImport.parse("Title,Status,Due date,Due time,Reminder enabled,Repeat\nA,Open,,,,\n").error!!.contains("headers"))
        assertTrue(TaskCsvImport.parse("Task,Status,Due date,Due time,Reminder enabled,Repeat\n\"unfinished,Open,,,,\n").error!!.contains("quoting"))
        assertTrue(TaskCsvImport.parse("Task,Status,Due date,Due time,Reminder enabled,Repeat\nA,Open\n").error!!.contains("six columns"))
        assertTrue(TaskCsvImport.parse("Task,Status,Due date,Due time,Reminder enabled,Repeat\nA,Open,2026-02-30,,No,Never\n").error!!.contains("date or time"))
    }

    @Test fun rejectsInvalidUtf8AndInputsOverBoundedLimits() {
        assertNull(TaskCsvImport.readUtf8Bounded(ByteArrayInputStream(byteArrayOf(0xc3.toByte(), 0x28))))
        assertNull(TaskCsvImport.readUtf8Bounded(ByteArrayInputStream(ByteArray(TaskCsvImport.MAX_BYTES + 1))))
        assertTrue(TaskCsvImport.parse("x".repeat(TaskCsvImport.MAX_BYTES + 1)).error!!.contains("1 MB"))
    }

    @Test fun capsImportAtFiveHundredRows() {
        val header = "Task,Status,Due date,Due time,Reminder enabled,Repeat\n"
        val row = "Study,Open,,,No,Never\n"
        assertTrue(TaskCsvImport.parse(header + row.repeat(TaskCsvImport.MAX_ROWS + 1)).error!!.contains("500 tasks"))
    }
}
