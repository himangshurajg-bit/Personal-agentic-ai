package com.myra.ultra.nativeapp

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WebForgeCoderAssistTest {
    @Test fun requestContainsExactUserTextButNoToolsOrProjectSideChannels() {
        val text = "--- FILE: src/Main.kt ---\n1\tfun main() = Unit\n--- END FILE: src/Main.kt ---\n\nUsing the attached file context above, respond to:\nExplain this file"
        val request = JSONObject(WebForgeCoderAssist.requestJson(text))
        val contents = request.getJSONArray("contents")
        assertEquals(1, contents.length())
        assertEquals(text, contents.getJSONObject(0).getJSONArray("parts").getJSONObject(0).getString("text"))
        assertFalse(request.has("tools"))
        assertTrue(request.getJSONObject("systemInstruction").toString().contains("no tools"))
        assertTrue(request.getJSONObject("systemInstruction").toString().contains("cannot inspect or change files"))
    }

    @Test fun validatesTaskAndCombinedRequestBounds() {
        assertTrue(WebForgeCoderAssist.validate(" ", "task") != null)
        assertTrue(WebForgeCoderAssist.validate("x".repeat(WebForgeCoderAssist.MAX_TASK_CHARS + 1), "x") != null)
        assertTrue(WebForgeCoderAssist.validate("task", "x".repeat(WebForgeCoderAssist.MAX_REQUEST_CHARS + 1)) != null)
        assertEquals(null, WebForgeCoderAssist.validate("Explain this", "Explain this"))
        assertTrue(runCatching { WebForgeCoderAssist.requestJson("x".repeat(WebForgeCoderAssist.MAX_REQUEST_CHARS + 1)) }.isFailure)
    }

    @Test fun patchRequestContainsOnlyOneExactFileAndTaskAndUsesJsonOutput() {
        val requestText = WebForgeCoderAssist.patchRequestText("Fix the button", "src/main.js", "const x = 1;\n")
        val json = JSONObject(WebForgeCoderAssist.patchRequestJson(requestText))
        assertEquals(requestText, json.getJSONArray("contents").getJSONObject(0).getJSONArray("parts").getJSONObject(0).getString("text"))
        assertEquals("application/json", json.getJSONObject("generationConfig").getString("responseMimeType"))
        assertFalse(json.has("tools"))
        assertTrue(json.getJSONObject("systemInstruction").toString().contains("complete replacement"))
        assertTrue(runCatching { WebForgeCoderAssist.patchRequestText("task", "../outside", "file") }.isFailure)
        assertTrue(runCatching { WebForgeCoderAssist.patchRequestText("task", ".hidden/file", "file") }.isFailure)
        assertTrue(runCatching { WebForgeCoderAssist.patchRequestText("task", "C:\\secret", "file") }.isFailure)
        assertTrue(runCatching { WebForgeCoderAssist.patchRequestText("task", "ok.txt", "x".repeat(WebForgeCoderAssist.MAX_PATCH_OUTPUT_CHARS + 1)) }.isFailure)
    }

    @Test fun parserAcceptsOnlyBoundedCompleteReplacementJson() {
        fun response(text: String, finish: String = "STOP"): String = JSONObject()
            .put("candidates", JSONArray().put(JSONObject().put("finishReason", finish).put("content", JSONObject().put("parts", JSONArray().put(JSONObject().put("text", text))))))
            .toString()
        val replacement = "<!doctype html>\n<h1>ok</h1>\n"
        val valid = response(JSONObject().put("replacement", replacement).toString())
        assertEquals(replacement, WebForgeCoderAssist.parsePatchReplacement(valid))
        listOf("plain prose", "```json\n{}\n```", "{}", "{\"replacement\":null}", "{\"replacement\":\"\",\"extra\":1}").forEach { invalid ->
            assertTrue("Expected invalid response: $invalid", runCatching { WebForgeCoderAssist.parsePatchReplacement(response(invalid)) }.isFailure)
        }
        assertTrue(runCatching { WebForgeCoderAssist.parsePatchReplacement(response("{\"replacement\":\"x\"}", "MAX_TOKENS")) }.isFailure)
        val tooLarge = JSONObject().put("replacement", "x".repeat(WebForgeCoderAssist.MAX_PATCH_OUTPUT_CHARS + 1)).toString()
        assertTrue(runCatching { WebForgeCoderAssist.parsePatchReplacement(response(tooLarge)) }.isFailure)
        assertNotNull(valid)
    }

    @Test fun parsesOnlyBoundedPlainCandidateText() {
        val api = JSONObject().put("candidates", JSONArray().put(JSONObject().put("content", JSONObject().put("parts", JSONArray().put(JSONObject().put("text", "Review this suggestion"))))))
        assertEquals("Review this suggestion", WebForgeCoderAssist.parseResponse(api.toString()))
        assertTrue(runCatching { WebForgeCoderAssist.parseResponse("{}") }.isFailure)
        assertTrue(runCatching { WebForgeCoderAssist.parseResponse(" ".repeat(WebForgeCoderAssist.MAX_RESPONSE_CHARS + 1)) }.isFailure)
    }
}
