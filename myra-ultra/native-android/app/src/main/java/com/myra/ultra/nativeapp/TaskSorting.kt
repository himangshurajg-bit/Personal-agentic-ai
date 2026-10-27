package com.myra.ultra.nativeapp
import java.util.Locale


internal enum class TaskSortMode(val label: String) {
    MANUAL("Manual order"),
    DUE_SOON("Due soon"),
    TITLE("Title A–Z"),
}

/** Sorts a filtered task view without mutating the user's saved task order or records. */
internal fun sortTasks(tasks: List<MyraTask>, mode: TaskSortMode): List<MyraTask> = when (mode) {
    TaskSortMode.MANUAL -> tasks.toList()
    TaskSortMode.TITLE -> tasks.withIndex()
        .sortedWith(compareBy<IndexedValue<MyraTask>> { it.value.title.trim().lowercase(Locale.ROOT) }.thenBy { it.index })
        .map { it.value }
    TaskSortMode.DUE_SOON -> tasks.withIndex()
        .sortedWith(
            compareBy<IndexedValue<MyraTask>> { it.value.done }
                .thenBy { it.value.dueAtMillis == null }
                .thenBy { it.value.dueAtMillis ?: Long.MAX_VALUE }
                .thenBy { it.index },
        )
        .map { it.value }
}
