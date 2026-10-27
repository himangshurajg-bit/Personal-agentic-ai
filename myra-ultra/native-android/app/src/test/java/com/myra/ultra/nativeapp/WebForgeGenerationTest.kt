package com.myra.ultra.nativeapp

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WebForgeGenerationTest {
    @Test fun requestContainsOnlyExplicitPromptAndFixedGenerationRules() {
        val prompt = "Build a small flower shop page"
        val request = JSONObject(WebForgeGeneration.requestJson(prompt))
        val contents = request.getJSONArray("contents")
        assertEquals(1, contents.length())
        val content = contents.getJSONObject(0)
        assertEquals("user", content.getString("role"))
        assertEquals(prompt, content.getJSONArray("parts").getJSONObject(0).getString("text"))
        assertFalse(request.toString().contains("index.html"))
        assertFalse(request.toString().contains("project files"))
        assertEquals("application/json", request.getJSONObject("generationConfig").getString("responseMimeType"))
        assertTrue(request.getJSONObject("systemInstruction").toString().contains("Do not use external URLs"))
    }

    @Test fun promptLengthIsBoundedAndWhitespaceOnlyPromptIsRejected() {
        assertTrue(WebForgeGeneration.validatePrompt(" \n") != null)
        assertTrue(WebForgeGeneration.validatePrompt("x".repeat(WebForgeGeneration.MAX_PROMPT_CHARS + 1)) != null)
        assertEquals(null, WebForgeGeneration.validatePrompt("A portfolio"))
    }

    @Test fun parsesBoundedGeminiDraftIntoReviewableHtmlCssAndJs() {
        val generated = WebForgeGeneration.parseResponse(response("A Site", "<html><head><title>A</title></head><body>A</body></html>", "body { color: teal; }", "document.title = 'A';"))
        assertEquals("A Site", generated.projectName)
        assertEquals("body { color: teal; }", generated.files.css)
        assertEquals("document.title = 'A';", generated.files.js)
        assertTrue(generated.files.html.startsWith("<html>"))
    }

    @Test fun unsafeProjectNameFallsBackToEditableSafeName() {
        val generated = WebForgeGeneration.parseResponse(response("../outside", "<html/>", "body {}", ""))
        assertEquals("Generated Site", generated.projectName)
    }

    @Test fun rejectsMissingFieldsOversizedFilesAndOversizedResponse() {
        val missingCss = response("Site", "<html/>", "", "")
        assertTrue(runCatching { WebForgeGeneration.parseResponse(missingCss) }.isFailure)
        val largeCss = response("Site", "<html/>", "x".repeat(WebForgeRepository.MAX_FILE_CHARS + 1), "")
        assertTrue(runCatching { WebForgeGeneration.parseResponse(largeCss) }.isFailure)
        assertTrue(runCatching { WebForgeGeneration.parseResponse(" ".repeat(WebForgeGeneration.MAX_RESPONSE_CHARS + 1)) }.isFailure)
    }

    @Test fun generatedProjectIsCreatedWithReviewedFilesAndExistingProjectsAreNeverOverwritten() {
        val root = java.nio.file.Files.createTempDirectory("webforge-generated").toFile()
        try {
            val repository = WebForgeRepository(root)
            val original = repository.createProject("My Site", WebForgeFiles("<h1>old</h1>", "old {}", ""))
            val generated = WebForgeFiles("<h1>reviewed</h1>", "new {}", "alert('local preview only')")
            val newProject = repository.createProject("My Site", generated)
            assertEquals("my-site-2", newProject.id)
            assertEquals(generated, repository.readProject(newProject.id))
            assertEquals("<h1>old</h1>", repository.readProject(original.id).html)
        } finally {
            root.deleteRecursively()
        }
    }

    private fun response(name: String, html: String, css: String, js: String): String {
        val result = JSONObject()
            .put("project_name", name)
            .put("html", html)
            .put("css", css)
            .put("javascript", js)
        val api = JSONObject().put("candidates", JSONArray().put(JSONObject().put("content", JSONObject().put("parts", JSONArray().put(JSONObject().put("text", result.toString()))))))
        return api.toString()
    }
}
