package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Test

class TaskQueryTest {
    private val tasks = listOf(
        MyraTask("1", "Review Android plan", false),
        MyraTask("2", "Ship release notes", true),
        MyraTask("3", "Review image flow", true),
    )

    @Test fun filtersByStatusWithoutChangingOrder() {
        assertEquals(listOf(tasks[0]), filterTasks(tasks, "", TaskFilter.OPEN))
        assertEquals(listOf(tasks[1], tasks[2]), filterTasks(tasks, "", TaskFilter.COMPLETED))
        assertEquals(tasks, filterTasks(tasks, "", TaskFilter.ALL))
    }

    @Test fun searchesTitlesCaseInsensitivelyAndTrimsQuery() {
        assertEquals(listOf(tasks[0], tasks[2]), filterTasks(tasks, "  REVIEW ", TaskFilter.ALL))
        assertEquals(listOf(tasks[2]), filterTasks(tasks, "image", TaskFilter.COMPLETED))
        assertEquals(emptyList<MyraTask>(), filterTasks(tasks, "missing", TaskFilter.ALL))
    }
}
