package dev.personalagent.personal_assistant

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class UserNotificationRequestTest {
    @Test
    fun acceptsExactBoundedPayloadIncludingReadableMultilineText() {
        val request = UserNotificationRequestParser.parse(
            mapOf("title" to "Study reminder", "text" to "Revise vectors\nThen take a break."),
        )
        assertEquals(UserNotificationRequest("Study reminder", "Revise vectors\nThen take a break."), request)
    }

    @Test
    fun rejectsMissingUnexpectedBlankOrOversizedFields() {
        assertNull(UserNotificationRequestParser.parse(null))
        assertNull(UserNotificationRequestParser.parse(mapOf("title" to "Title")))
        assertNull(UserNotificationRequestParser.parse(mapOf("title" to "Title", "text" to "Body", "extra" to true)))
        assertNull(UserNotificationRequestParser.parse(mapOf("title" to "  ", "text" to "Body")))
        assertNull(UserNotificationRequestParser.parse(mapOf("title" to "Title", "text" to "\n\t")))
        assertNull(UserNotificationRequestParser.parse(mapOf("title" to "x".repeat(UserNotificationRequestParser.TITLE_LIMIT + 1), "text" to "Body")))
        assertNull(UserNotificationRequestParser.parse(mapOf("title" to "Title", "text" to "x".repeat(UserNotificationRequestParser.TEXT_LIMIT + 1))))
    }

    @Test
    fun rejectsControlCharactersExceptOrdinaryTextLineBreaksAndTabs() {
        assertNull(UserNotificationRequestParser.parse(mapOf("title" to "bad\nTitle", "text" to "Body")))
        assertNull(UserNotificationRequestParser.parse(mapOf("title" to "Title", "text" to "bad\u0000Body")))
        assertEquals(
            UserNotificationRequest("Title", "line 1\nline 2\tcontinued"),
            UserNotificationRequestParser.parse(mapOf("title" to "Title", "text" to "line 1\nline 2\tcontinued")),
        )
    }
}
