package dev.personalagent.personal_assistant

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TextShareValidationTest {
    @Test fun acceptsNonEmptyTextWithinLimits() {
        assertTrue(isValidTextSharePayload("Review reply", "Hello"))
        assertTrue(isValidTextSharePayload("x".repeat(80), "y".repeat(10000)))
    }

    @Test fun rejectsMissingOrOversizedShareData() {
        assertFalse(isValidTextSharePayload(null, "Hello"))
        assertFalse(isValidTextSharePayload("   ", "Hello"))
        assertFalse(isValidTextSharePayload("Review reply", "  "))
        assertFalse(isValidTextSharePayload("x".repeat(81), "Hello"))
        assertFalse(isValidTextSharePayload("Review reply", "y".repeat(10001)))
    }
}
