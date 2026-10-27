package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class WebForgeCoderTodoTest {
    @get:Rule val temporaryFolder = TemporaryFolder()

    @Test fun fullOrderedTodoListPersistsPerProjectAndReplacesPreviousList() {
        val root = temporaryFolder.newFolder("projects")
        val repository = WebForgeRepository(root)
        val alpha = repository.createProject("Alpha")
        val beta = repository.createProject("Beta")
        val initial = listOf(
            WebForgeTodo("plan", "Plan the page", WebForgeTodoStatus.IN_PROGRESS),
            WebForgeTodo("review", "Review the files", WebForgeTodoStatus.PENDING),
        )
        repository.replaceCoderTodos(alpha.id, initial)
        assertEquals(initial, repository.loadCoderTodos(alpha.id))
        assertTrue(repository.loadCoderTodos(beta.id).isEmpty())

        val replacement = listOf(WebForgeTodo("plan", "Plan the page", WebForgeTodoStatus.COMPLETED))
        repository.replaceCoderTodos(alpha.id, replacement)
        val reopened = WebForgeRepository(root)
        assertEquals(replacement, reopened.loadCoderTodos(alpha.id))
        assertTrue(reopened.loadCoderTodos(beta.id).isEmpty())
    }

    @Test fun rejectsEmptyDuplicateOversizedAndBlankTasksWithoutChangingSavedList() {
        val repository = WebForgeRepository(temporaryFolder.newFolder("projects"))
        val project = repository.createProject("Bounds")
        val valid = listOf(WebForgeTodo("one", "One", WebForgeTodoStatus.PENDING))
        repository.replaceCoderTodos(project.id, valid)
        val invalidLists = listOf(
            emptyList(),
            listOf(valid.single(), valid.single()),
            listOf(WebForgeTodo("blank", "  ", WebForgeTodoStatus.PENDING)),
            listOf(WebForgeTodo("long", "x".repeat(WebForgeRepository.MAX_CODER_TODO_CHARS + 1), WebForgeTodoStatus.PENDING)),
        )
        invalidLists.forEach { bad -> assertTrue(runCatching { repository.replaceCoderTodos(project.id, bad) }.isFailure) }
        assertEquals(valid, repository.loadCoderTodos(project.id))
    }
}
