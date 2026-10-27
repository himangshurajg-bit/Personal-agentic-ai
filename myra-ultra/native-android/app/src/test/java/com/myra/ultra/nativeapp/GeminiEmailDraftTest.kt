package com.myra.ultra.nativeapp

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class GeminiEmailDraftTest {
    private val url = "mailto:alex@example.com?subject=Hello%20there&body=First%20line%0ASecond%20line"

    @Test fun parsesBoundedSingleRecipientSubjectAndBodyAndBuildsSendToIntent() {
        val request = GeminiSafeTools.emailDraftRequest(JSONObject().put("url", url))
        assertEquals("alex@example.com", request.recipient)
        assertEquals("Hello there", request.subject)
        assertEquals("First line\nSecond line", request.body)
        assertEquals(GeminiSafeTools.OPEN_EMAIL_DRAFT, GeminiSafeTools.validate(GeminiSafeTools.OPEN_EMAIL_DRAFT, JSONObject().put("url", url)))
        val intent = GeminiSafeTools.emailDraftIntent(request)
        assertEquals("android.intent.action.SENDTO", intent.action)
        assertEquals(url, intent.data)
        val declaration = GeminiSafeTools.declaration().getJSONArray("functionDeclarations")
            .let { items -> (0 until items.length()).map { items.getJSONObject(it) }.single { it.getString("name") == GeminiSafeTools.OPEN_EMAIL_DRAFT } }
        assertTrue(declaration.getString("description").contains("never sends"))
        assertTrue(declaration.getString("description").contains("approval"))
    }

    @Test fun emailDraftNeedsOneExactExplicitLatestTurnMailtoRequest() {
        assertTrue(GeminiSafeTools.hasExplicitEmailDraftIntent("Open this mailto link: $url", url))
        assertTrue(GeminiSafeTools.hasExplicitEmailDraftIntent("Please compose an email using $url", url))
        assertEquals(false, GeminiSafeTools.hasExplicitEmailDraftIntent("Here is the link $url", url))
        assertEquals(false, GeminiSafeTools.hasExplicitEmailDraftIntent("Send this email: $url", url))
        assertEquals(false, GeminiSafeTools.hasExplicitEmailDraftIntent("Don't open this mailto link: $url", url))
        assertEquals(false, GeminiSafeTools.hasExplicitEmailDraftIntent("Open this mailto link: $url and mailto:kim@example.com", url))
        assertEquals(false, GeminiSafeTools.hasExplicitEmailDraftIntent("Open https://example.com", url))
    }

    @Test fun rejectsUnsupportedOrAmbiguousMailtoPayloads() {
        listOf(
            "https://example.com",
            "mailto:alex@example.com,kim@example.com",
            "mailto:alex@example.com?bcc=secret@example.com",
            "mailto:alex@example.com?subject=one&subject=two",
            "mailto:alex@example.com?subject=bad%0Aheader",
            "mailto:alex@example.com?body=${"x".repeat(2001)}",
            "mailto:alex@example.com%ZZ",
            "mailto:alex%40example.com#fragment",
        ).forEach { candidate ->
            try {
                GeminiSafeTools.emailDraftRequest(JSONObject().put("url", candidate))
                throw AssertionError("Expected rejection for $candidate")
            } catch (_: java.io.IOException) { }
        }
        listOf(
            JSONObject(),
            JSONObject().put("url", url).put("extra", true),
            JSONObject().put("url", 7),
        ).forEach { args ->
            try { GeminiSafeTools.validate(GeminiSafeTools.OPEN_EMAIL_DRAFT, args); throw AssertionError("Expected rejection") }
            catch (_: java.io.IOException) { }
        }
    }

    @Test fun emailDraftIntentRejectsTamperedPreviewFields() {
        val parsed = GeminiSafeTools.emailDraftRequest(JSONObject().put("url", url))
        val changed = parsed.copy(subject = "different")
        try { GeminiSafeTools.emailDraftIntent(changed); throw AssertionError("Expected changed draft rejection") }
        catch (_: java.io.IOException) { }
    }
}
