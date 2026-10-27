package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotSame
import org.junit.Test

class TaskSortingTest {
    private val tasks = listOf(
        MyraTask("a", "Zebra", false, dueAtMillis = 30L),
        MyraTask("b", "no date", false),
        MyraTask("c", "Alpha", true, dueAtMillis = 1L),
        MyraTask("d", "alpha", false, dueAtMillis = 10L),
        MyraTask("e", "Done, no date", true),
    )

    @Test fun manualModeKeepsInputOrderAndReturnsASeparateList() {
        val sorted = sortTasks(tasks, TaskSortMode.MANUAL)
        assertEquals(tasks, sorted)
        assertNotSame(tasks, sorted)
    }

    @Test fun dueSoonPutsOpenDatedTasksFirstThenUndatedThenCompleted() {
        assertEquals(listOf("d", "a", "b", "c", "e"), sortTasks(tasks, TaskSortMode.DUE_SOON).map { it.id })
    }

    @Test fun titleSortIgnoresCaseAndKeepsStableOrderForTies() {
        assertEquals(listOf("c", "d", "e", "b", "a"), sortTasks(tasks, TaskSortMode.TITLE).map { it.id })
    }

    @Test fun sortingFilteredSubsetDoesNotAddTasksBack() {
        val filtered = filterTasks(tasks, "alpha", TaskFilter.ALL)
        assertEquals(listOf("d", "c"), sortTasks(filtered, TaskSortMode.DUE_SOON).map { it.id })
    }
}
