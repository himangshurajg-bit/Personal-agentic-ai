package com.myra.ultra.nativeapp

import java.io.IOException
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GeminiNotificationTest {
    @Test fun acceptsOnlyExactBoundedNonblankContent() {
        val request = GeminiNotificationPolicy.request(JSONObject().put("title", "Study check").put("text", "Open the practice set now."))
        assertEquals("Study check", request.title)
        assertEquals("Open the practice set now.", request.text)
        assertEquals(GeminiNotificationPolicy.TITLE_LIMIT, GeminiNotificationPolicy.request(JSONObject()
            .put("title", "t".repeat(GeminiNotificationPolicy.TITLE_LIMIT)).put("text", "body")).title.length)
        assertEquals(GeminiNotificationPolicy.TEXT_LIMIT, GeminiNotificationPolicy.request(JSONObject()
            .put("title", "Title").put("text", "x".repeat(GeminiNotificationPolicy.TEXT_LIMIT))).text.length)
    }

    @Test fun rejectsUnexpectedTypesAndUnsafeOrOversizedContent() {
        listOf(
            JSONObject(),
            JSONObject().put("title", "Title").put("text", "Body").put("extra", "unexpected"),
            JSONObject().put("title", "").put("text", "Body"),
            JSONObject().put("title", "Title".repeat(30)).put("text", "Body"),
            JSONObject().put("title", "Title").put("text", "x".repeat(GeminiNotificationPolicy.TEXT_LIMIT + 1)),
            JSONObject().put("title", "Bad\nTitle").put("text", "Body"),
            JSONObject().put("title", "Title").put("text", "Bad\u0000body"),
            JSONObject().put("title", 3).put("text", "Body"),
        ).forEach { args -> expectRejected { GeminiNotificationPolicy.request(args) } }
    }

    @Test fun explicitLatestTurnMustRequestANotificationOrAlert() {
        listOf("show me a notification saying take a break", "please post an alert", "notify me now")
            .forEach { assertTrue(it, GeminiNotificationPolicy.hasExplicitIntent(it)) }
        listOf("what is a notification?", "don't notify me", "show me the battery status", "make a reminder", "notify me when the timer ends", "post a notification later", "notify me at 4")
            .forEach { assertFalse(it, GeminiNotificationPolicy.hasExplicitIntent(it)) }
    }

    private fun expectRejected(block: () -> Unit) {
        try { block() } catch (_: IOException) { return }
        throw AssertionError("Expected notification request to be rejected")
    }
}
