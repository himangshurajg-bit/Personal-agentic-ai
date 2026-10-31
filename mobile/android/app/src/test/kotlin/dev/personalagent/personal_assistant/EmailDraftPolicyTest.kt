package dev.personalagent.personal_assistant

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class EmailDraftPolicyTest {
    @Test fun `accepts one valid recipient and bounded draft fields`() {
        assertEquals(
            EmailDraftRequest("student@example.com", "Hello", "Line one\nLine two"),
            EmailDraftPolicy.parse(" student@example.com ", "Hello", "Line one\nLine two"),
        )
        assertNull(EmailDraftPolicy.parse("a@example.com,b@example.com", "Hi", "Body"))
        assertNull(EmailDraftPolicy.parse("not-an-email", "Hi", "Body"))
        assertNull(EmailDraftPolicy.parse("student@example.com", "x".repeat(201), "Body"))
        assertNull(EmailDraftPolicy.parse("student@example.com", "Hi", "x".repeat(10_001)))
        assertNull(EmailDraftPolicy.parse("student@example.com", "Hi", " \n"))
    }

    @Test fun `mailto encodes subject and body without sending`() {
        val request = requireNotNull(EmailDraftPolicy.parse("student+jee@example.com", "A & B", "Hi there\nPlease review"))
        val uri = EmailDraftPolicy.mailto(request)
        assertEquals(
            "mailto:student+jee@example.com?subject=A%20%26%20B&body=Hi%20there%0APlease%20review",
            uri,
        )
    }
}
