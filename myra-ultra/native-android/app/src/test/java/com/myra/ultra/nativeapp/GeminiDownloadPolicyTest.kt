package com.myra.ultra.nativeapp

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class GeminiDownloadPolicyTest {
    @Test fun validatesOnlyOneCredentialFreeHttpUrlAndSanitizesName() {
        val request = GeminiDownloadPolicy.request(JSONObject().put("url", "https://example.test/files/My%20report.pdf"))
        assertEquals("My report.pdf", request.fileName)
        assertEquals("https://example.test/files/My%20report.pdf", request.url)
        assertNull(DownloadData.validate("https://user:password@example.test/private.pdf"))
        assertNull(DownloadData.validate("file:///private/data"))
    }

    @Test fun rejectsExtraArgumentsAndInvalidUrls() {
        listOf(
            JSONObject().put("url", "https://example.test/a.pdf").put("extra", true),
            JSONObject().put("url", "ftp://example.test/a.pdf"),
            JSONObject().put("url", "https://user:pass@example.test/a.pdf"),
            JSONObject().put("url", " "),
        ).forEach { args ->
            try {
                GeminiDownloadPolicy.request(args)
                fail("Expected invalid download request to be rejected")
            } catch (_: java.io.IOException) { }
        }
    }

    @Test fun declaresOnlyTheExplicitUrlArgumentAndValidatesThroughSafeToolRegistry() {
        val declarations = GeminiSafeTools.declaration().getJSONArray("functionDeclarations")
        val declaration = (0 until declarations.length())
            .map { declarations.getJSONObject(it) }
            .first { it.getString("name") == GeminiDownloadPolicy.TOOL }
        val parameters = declaration.getJSONObject("parameters")
        assertEquals("OBJECT", parameters.getString("type"))
        assertEquals("STRING", parameters.getJSONObject("properties").getJSONObject("url").getString("type"))
        assertEquals("url", parameters.getJSONArray("required").getString(0))
        assertEquals(GeminiDownloadPolicy.TOOL, GeminiSafeTools.validate(
            GeminiDownloadPolicy.TOOL,
            JSONObject().put("url", "https://example.test/report.pdf"),
        ))
    }

    @Test fun requiresExactUrlAndDirectDownloadIntentInLatestMessage() {
        val request = GeminiDownloadPolicy.request(JSONObject().put("url", "https://example.test/report.pdf"))
        assertTrue(GeminiDownloadPolicy.hasExplicitIntent("Download https://example.test/report.pdf", request))
        assertFalse(GeminiDownloadPolicy.hasExplicitIntent("Open https://example.test/report.pdf", request))
        assertFalse(GeminiDownloadPolicy.hasExplicitIntent("Download https://example.test/other.pdf", request))
        assertFalse(GeminiDownloadPolicy.hasExplicitIntent("Don't download https://example.test/report.pdf", request))
        assertFalse(GeminiDownloadPolicy.hasExplicitIntent("If I ask later, download https://example.test/report.pdf", request))
    }
}
