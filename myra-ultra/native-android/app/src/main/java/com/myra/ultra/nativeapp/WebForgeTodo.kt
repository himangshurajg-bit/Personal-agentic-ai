package com.myra.ultra.nativeapp

/** Project-local counterpart to MYRA Coder's update_todos items. */
internal enum class WebForgeTodoStatus(val value: String) {
    PENDING("pending"), IN_PROGRESS("in_progress"), COMPLETED("completed"), FAILED("failed");

    companion object {
        fun parse(value: String): WebForgeTodoStatus = entries.firstOrNull { it.value == value }
            ?: throw IllegalArgumentException("Unknown Coder task status.")
    }
}

internal data class WebForgeTodo(val id: String, val content: String, val status: WebForgeTodoStatus)
