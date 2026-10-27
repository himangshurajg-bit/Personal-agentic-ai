package com.myra.ultra.nativeapp

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performScrollTo
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class NativeAppSmokeTest {
    @get:Rule
    val compose = createAndroidComposeRule<MainActivity>()

    @Before
    fun disableAutoAdvanceForAnimatedTransitions() {
        // Advance finite screen transitions explicitly; live voice animation is exercised separately.
        compose.mainClock.autoAdvance = false
    }

    private fun markStage(name: String) {
        android.util.Log.i("NativeAppSmokeTest", name)
    }

    private fun openScreen(label: String) {
        markStage("open $label: start")
        compose.onNodeWithText(label).performClick()
        markStage("open $label: clicked")
        // Advance the screen transition without a global idle wait; Tasks can keep Compose busy.
        compose.mainClock.advanceTimeBy(500L)
        markStage("open $label: animation advanced")
    }

    @Test
    fun implementedScreensOpenAndShowTheirCurrentScope() {
        markStage("home: assert")
        compose.onNodeWithText("Namaste").assertIsDisplayed()

        openScreen("Chat")
        compose.onNodeWithText("Up to 100 messages are saved on this device.").assertIsDisplayed()
        markStage("chat: message cap asserted")
        markStage("chat: composer check start")
        compose.onNodeWithText("Message MYRA…", useUnmergedTree = true).assertIsDisplayed()
        markStage("chat: composer asserted")
        markStage("chat: asserted")

        openScreen("Tasks")
        compose.onNodeWithText("Search, due dates, and optional local reminders.").assertIsDisplayed()
        val title = "emulator smoke task"
        compose.onNodeWithText("Add a task").performTextInput(title)
        compose.onNodeWithContentDescription("Add task").performClick()
        compose.onNodeWithText(title).assertIsDisplayed()
        val completionToggle = compose.onNodeWithContentDescription("Mark $title as complete")
        completionToggle.performScrollTo()
        compose.mainClock.advanceTimeBy(500L)
        compose.waitForIdle()
        completionToggle.assertIsDisplayed().performClick()
        compose.onNodeWithText("Completed").performClick()
        compose.onNodeWithText(title).assertIsDisplayed()
        compose.onNodeWithText("Open").performClick()
        compose.onNodeWithText("No tasks match this search and filter.").assertIsDisplayed()
        compose.onNodeWithText("All").performClick()
        compose.onNodeWithText(title).assertIsDisplayed()
        compose.onNodeWithContentDescription("Mark $title as open").performClick()
        compose.onNodeWithContentDescription("Delete task").performClick()
        compose.onNodeWithText("No tasks yet. Add one above.").assertIsDisplayed()
        markStage("tasks: add, complete, filter and delete asserted")

        openScreen("Tools")
        compose.onNodeWithText("Only explicit, user-tapped actions are active.").assertIsDisplayed()
        // Keep auto-advance off for the orb's infinite animation. Advance the finite bring-into-view
        // scroll explicitly before checking the off-screen control.
        markStage("tools: scroll start")
        compose.onNodeWithText("Web search").performScrollTo()
        markStage("tools: scroll requested")
        compose.mainClock.advanceTimeBy(500L)
        compose.waitForIdle()
        compose.onNodeWithText("Web search").assertIsDisplayed()
        markStage("tools: web search asserted")

        openScreen("Files")
        compose.onNodeWithText("Choose a file to inspect it locally.").assertIsDisplayed()
        compose.onNodeWithText("Choose file").assertIsDisplayed()
        markStage("files: asserted")

        openScreen("Settings")
        compose.onNodeWithText("Gemini API key").assertIsDisplayed()
        compose.onNodeWithText("Language").assertIsDisplayed()
        markStage("settings: asserted")
    }
}
