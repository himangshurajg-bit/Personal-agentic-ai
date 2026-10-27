package com.myra.ultra.nativeapp

import java.util.Base64

data class LocalWorkflowStep(val id: String, val title: String, val done: Boolean = false)
data class LocalWorkflow(val id: String, val title: String, val steps: List<LocalWorkflowStep> = emptyList())

data class WorkflowProgress(val completed: Int, val total: Int) {
    val isComplete: Boolean get() = total > 0 && completed == total
    val nextIndex: Int get() = if (isComplete) -1 else completed
}

/** A private, user-edited sequence. It coordinates only checklist progress, never external actions. */
object LocalWorkflowPlan {
    const val MAX_WORKFLOWS = 50
    const val MAX_STEPS = 50
    const val MAX_TITLE_CHARS = 80
    const val MAX_STEP_CHARS = 160

    fun progress(workflow: LocalWorkflow): WorkflowProgress {
        val completed = workflow.steps.takeWhile { it.done }.size
        return WorkflowProgress(completed, workflow.steps.size)
    }

    fun addWorkflow(workflows: List<LocalWorkflow>, title: String, id: String): List<LocalWorkflow>? {
        val clean = title.trim()
        if (clean.isEmpty() || clean.length > MAX_TITLE_CHARS || id.isBlank() || workflows.size >= MAX_WORKFLOWS || workflows.any { it.id == id }) return null
        return workflows + LocalWorkflow(id = id, title = clean)
    }

    fun addStep(workflow: LocalWorkflow, title: String, id: String): LocalWorkflow? {
        val clean = title.trim()
        if (clean.isEmpty() || clean.length > MAX_STEP_CHARS || id.isBlank() || workflow.steps.size >= MAX_STEPS || workflow.steps.any { it.id == id }) return null
        return workflow.copy(steps = workflow.steps + LocalWorkflowStep(id, clean))
    }

    /** Reorders within the completed or pending section so sequential progress remains truthful. */
    fun moveStep(workflow: LocalWorkflow, stepId: String, direction: Int): LocalWorkflow? {
        if (direction !in setOf(-1, 1)) return null
        val index = workflow.steps.indexOfFirst { it.id == stepId }
        val target = index + direction
        if (index < 0 || target !in workflow.steps.indices || workflow.steps[index].done != workflow.steps[target].done) return null
        val reordered = workflow.steps.toMutableList()
        val item = reordered[index]
        reordered[index] = reordered[target]
        reordered[target] = item
        return workflow.copy(steps = reordered)
    }

    fun removeStep(workflow: LocalWorkflow, stepId: String): LocalWorkflow? {
        if (workflow.steps.none { it.id == stepId }) return null
        return workflow.copy(steps = workflow.steps.filterNot { it.id == stepId })
    }

    fun removeWorkflow(workflows: List<LocalWorkflow>, workflowId: String): List<LocalWorkflow>? {
        if (workflows.none { it.id == workflowId }) return null
        return workflows.filterNot { it.id == workflowId }
    }

    fun completeNext(workflow: LocalWorkflow): LocalWorkflow? {
        val index = progress(workflow).nextIndex
        if (index < 0) return null
        return workflow.copy(steps = workflow.steps.mapIndexed { i, step -> if (i == index) step.copy(done = true) else step })
    }

    fun reset(workflow: LocalWorkflow): LocalWorkflow = workflow.copy(steps = workflow.steps.map { it.copy(done = false) })

    fun encode(workflows: List<LocalWorkflow>): String = workflows.joinToString("\n") { workflow ->
        val title = encodeText(workflow.title)
        val steps = workflow.steps.joinToString(",") { step ->
            "${encodeText(step.id)}:${if (step.done) "1" else "0"}:${encodeText(step.title)}"
        }
        "${encodeText(workflow.id)}|$title|$steps"
    }

    fun decode(serialized: String): List<LocalWorkflow> = serialized.lineSequence().mapNotNull { row ->
        try {
            val fields = row.split('|', limit = 3)
            if (fields.size != 3) return@mapNotNull null
            val id = decodeText(fields[0]); val title = decodeText(fields[1])
            if (id.isBlank() || title.isBlank() || title.length > MAX_TITLE_CHARS) return@mapNotNull null
            val steps = if (fields[2].isEmpty()) emptyList() else fields[2].split(',').map { encoded ->
                val parts = encoded.split(':', limit = 3)
                require(parts.size == 3 && parts[1] in setOf("0", "1"))
                val stepId = decodeText(parts[0]); val stepTitle = decodeText(parts[2])
                require(stepId.isNotBlank() && stepTitle.isNotBlank() && stepTitle.length <= MAX_STEP_CHARS)
                LocalWorkflowStep(stepId, stepTitle, parts[1] == "1")
            }
            require(steps.size <= MAX_STEPS && steps.map { it.id }.distinct().size == steps.size)
            require(steps.takeWhile { it.done }.size == steps.count { it.done })
            LocalWorkflow(id, title, steps)
        } catch (_: Exception) { null }
    }.take(MAX_WORKFLOWS).toList()

    private fun encodeText(value: String): String = Base64.getUrlEncoder().withoutPadding().encodeToString(value.toByteArray(Charsets.UTF_8))
    private fun decodeText(value: String): String = String(Base64.getUrlDecoder().decode(value), Charsets.UTF_8)
}
