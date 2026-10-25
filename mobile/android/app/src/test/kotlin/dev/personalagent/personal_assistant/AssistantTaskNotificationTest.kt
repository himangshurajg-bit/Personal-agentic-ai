package dev.personalagent.personal_assistant

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AssistantTaskNotificationTest {
    @Test
    fun notificationPermissionFallsBackWithoutPrompting() {
        assertTrue(canPostAssistantTaskNotification(32, false))
        assertTrue(canPostAssistantTaskNotification(33, true))
        assertFalse(canPostAssistantTaskNotification(33, false))
    }

    @Test
    fun onlyKnownTaskStatusesAreShown() {
        assertEquals("Preparing your request", assistantTaskStatusLabel("preparing"))
        assertEquals("Running the on-device model", assistantTaskStatusLabel("workingOffline"))
        assertNull(assistantTaskStatusLabel("unknown"))
    }
}
