package com.myra.ultra.nativeapp

internal enum class TaskFilter {
    ALL,
    OPEN,
    COMPLETED,
}

/** Filters the locally stored task list without changing its order or persisted records. */
internal fun filterTasks(tasks: List<MyraTask>, query: String, filter: TaskFilter): List<MyraTask> {
    val normalizedQuery = query.trim()
    return tasks.filter { task ->
        val matchesStatus = when (filter) {
            TaskFilter.ALL -> true
            TaskFilter.OPEN -> !task.done
            TaskFilter.COMPLETED -> task.done
        }
        matchesStatus && (normalizedQuery.isEmpty() || task.title.contains(normalizedQuery, ignoreCase = true))
    }
}
