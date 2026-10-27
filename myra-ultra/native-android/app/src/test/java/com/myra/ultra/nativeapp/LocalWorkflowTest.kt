package com.myra.ultra.nativeapp

import org.junit.Assert.*
import org.junit.Test

class LocalWorkflowTest {
    @Test fun persistsUnicodeTextAndSequentialProgress() {
        val base = LocalWorkflowPlan.addWorkflow(emptyList(), "Study plan", "w1")!!.single()
        val withFirst = LocalWorkflowPlan.addStep(base, "Read physics chapter", "s1")!!
        val withSecond = LocalWorkflowPlan.addStep(withFirst, "Solve 10 problems", "s2")!!
        val withThird = LocalWorkflowPlan.addStep(withSecond, "Review answers", "s3")!!
        val afterOne = LocalWorkflowPlan.completeNext(withThird)!!
        assertEquals(1, LocalWorkflowPlan.progress(afterOne).completed)
        assertTrue(afterOne.steps[0].done)
        assertFalse(afterOne.steps[1].done)
        val afterTwo = LocalWorkflowPlan.completeNext(afterOne)!!
        assertFalse(LocalWorkflowPlan.progress(afterTwo).isComplete)
        val afterThree = LocalWorkflowPlan.completeNext(afterTwo)!!
        assertTrue(LocalWorkflowPlan.progress(afterThree).isComplete)
        assertNull(LocalWorkflowPlan.completeNext(afterThree))
        val unicode = afterThree.copy(title = "পঢ়া 📚", steps = afterThree.steps.map { it.copy(title = it.title + " ✓") })
        assertEquals(listOf(unicode), LocalWorkflowPlan.decode(LocalWorkflowPlan.encode(listOf(unicode))))
    }

    @Test fun enforcesBoundsAndUniqueIds() {
        assertNull(LocalWorkflowPlan.addWorkflow(emptyList(), " ", "x"))
        assertNull(LocalWorkflowPlan.addWorkflow(emptyList(), "x".repeat(81), "x"))
        val one = LocalWorkflowPlan.addWorkflow(emptyList(), "Valid", "w")!!.single()
        assertNull(LocalWorkflowPlan.addWorkflow(listOf(one), "Other", "w"))
        assertNull(LocalWorkflowPlan.addStep(one, "", "s"))
        assertNull(LocalWorkflowPlan.addStep(one, "x".repeat(161), "s"))
        assertNull(LocalWorkflowPlan.addStep(one, "Okay", ""))
    }

    @Test fun reorderStaysWithinProgressSectionAndRemovalPreservesSequentialProgress() {
        val workflow = LocalWorkflow(
            "w", "Plan", listOf(
                LocalWorkflowStep("done-a", "Finished A", true),
                LocalWorkflowStep("done-b", "Finished B", true),
                LocalWorkflowStep("next", "Next", false),
                LocalWorkflowStep("later", "Later", false),
            ),
        )
        val reordered = LocalWorkflowPlan.moveStep(workflow, "later", -1)!!
        assertEquals(listOf("done-a", "done-b", "later", "next"), reordered.steps.map { it.id })
        assertEquals(2, LocalWorkflowPlan.progress(reordered).completed)
        assertNull(LocalWorkflowPlan.moveStep(workflow, "done-b", 1))
        assertNull(LocalWorkflowPlan.moveStep(workflow, "next", -1))
        assertNull(LocalWorkflowPlan.moveStep(workflow, "next", 0))

        val withoutCompleted = LocalWorkflowPlan.removeStep(workflow, "done-a")!!
        assertEquals(1, LocalWorkflowPlan.progress(withoutCompleted).completed)
        val withoutPending = LocalWorkflowPlan.removeStep(withoutCompleted, "next")!!
        assertEquals(1, LocalWorkflowPlan.progress(withoutPending).completed)
        assertNull(LocalWorkflowPlan.removeStep(workflow, "missing"))
    }

    @Test fun deletingWorkflowRemovesOnlyTheSelectedPlan() {
        val workflows = listOf(LocalWorkflow("a", "A"), LocalWorkflow("b", "B"))
        assertEquals(listOf("b"), LocalWorkflowPlan.removeWorkflow(workflows, "a")!!.map { it.id })
        assertNull(LocalWorkflowPlan.removeWorkflow(workflows, "missing"))
    }

    @Test fun resetAndMalformedRowsStaySafe() {
        val w = LocalWorkflow("w", "Plan", listOf(LocalWorkflowStep("a", "A", true), LocalWorkflowStep("b", "B", true)))
        val reset = LocalWorkflowPlan.reset(w)
        assertEquals(0, LocalWorkflowPlan.progress(reset).completed)
        assertTrue(LocalWorkflowPlan.decode("bad|row\nnot-base64|x|x").isEmpty())
    }
}
