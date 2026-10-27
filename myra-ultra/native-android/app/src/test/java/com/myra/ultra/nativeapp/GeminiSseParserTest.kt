package com.myra.ultra.nativeapp

import java.io.IOException
import java.io.StringReader
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class GeminiSseParserTest {
    @Test fun emitsTextFromSuccessiveSseEvents() {
        val parser = GeminiSseParser()
        assertEquals(emptyList<GeminiSseEvent>(), parser.acceptLine(": keep-alive"))
        assertEquals(emptyList<GeminiSseEvent>(), parser.acceptLine("event: message"))
        assertEquals(emptyList<GeminiSseEvent>(), parser.acceptLine("data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"Hel\"}]}}]}"))
        assertEquals(listOf(GeminiSseEvent.Text("Hel")), parser.acceptLine(""))
        parser.acceptLine("data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"lo!\"}]}}]}")
        assertEquals(listOf(GeminiSseEvent.Text("lo!")), parser.finish())
        assertEquals(emptyList<GeminiSseEvent>(), parser.finish())
    }

    @Test fun supportsMultiplePartsAndIgnoresSafetyOrEmptyCandidates() {
        val parser = GeminiSseParser()
        parser.acceptLine("data: {\"promptFeedback\":{\"blockReason\":\"SAFETY\"}}")
        assertEquals(emptyList<GeminiSseEvent>(), parser.acceptLine(""))
        parser.acceptLine("data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"a\"},{\"text\":\"b\"},{\"inlineData\":{}}]}}]}")
        assertEquals(listOf(GeminiSseEvent.Text("a"), GeminiSseEvent.Text("b")), parser.acceptLine(""))
    }

    @Test fun handlesFinalEventWithoutTrailingBlankLine() {
        val parser = GeminiSseParser()
        parser.acceptLine("data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"final\"}]}}]}")
        assertEquals(listOf(GeminiSseEvent.Text("final")), parser.finish())
    }

    @Test fun parsesOnlyStructuredFunctionCallData() {
        val parser = GeminiSseParser()
        parser.acceptLine("data: {\"candidates\":[{\"content\":{\"parts\":[{\"functionCall\":{\"name\":\"get_battery_status\",\"args\":{}}}]}}]}")
        val events = parser.finish()
        assertEquals(1, events.size)
        val call = events.single() as GeminiSseEvent.FunctionCall
        assertEquals("get_battery_status", call.name)
        assertEquals(0, call.args.length())
    }

    @Test fun rejectsFunctionCallsWithoutNames() {
        val parser = GeminiSseParser()
        parser.acceptLine("data: {\"candidates\":[{\"content\":{\"parts\":[{\"functionCall\":{\"args\":{}}}]}}]}")
        try { parser.finish(); throw AssertionError("Expected invalid function call") }
        catch (error: IOException) { assertTrue(error.message!!.contains("without a name")) }
    }

    @Test fun exposesApiErrorWithoutTreatingItAsText() {
        val parser = GeminiSseParser()
        parser.acceptLine("data: {\"error\":{\"message\":\"quota exceeded\"}}")
        try { parser.acceptLine(""); throw AssertionError("Expected API stream error") }
        catch (error: IOException) { assertEquals("quota exceeded", error.message) }
    }

    @Test fun rejectsMalformedJsonAndOversizedEvents() {
        val malformed = GeminiSseParser()
        malformed.acceptLine("data: {nope}")
        try { malformed.finish(); throw AssertionError("Expected malformed event error") }
        catch (error: IOException) { assertTrue(error.message!!.contains("invalid stream event")) }
        val oversized = GeminiSseParser()
        try { oversized.acceptLine("data: ${"x".repeat(1_000_001)}"); throw AssertionError("Expected event size error") }
        catch (error: IOException) { assertTrue(error.message!!.contains("oversized")) }
    }
    @Test fun parserCountsSeparatorsTowardEventSizeLimit() {
        val parser = GeminiSseParser(maxEventChars = 4)
        parser.acceptLine("data: ab")
        try { parser.acceptLine("data: cd"); throw AssertionError("Expected event size error") }
        catch (error: IOException) { assertTrue(error.message!!.contains("oversized stream event")) }
    }

    @Test fun boundedLineReaderHandlesLfCrLfBareCrAndFinalUnterminatedLine() {
        val reader = BoundedSseLineReader(StringReader("one\r\ntwo\rthree\nfour"), maxLineChars = 5)
        assertEquals("one", reader.readLine())
        assertEquals("two", reader.readLine())
        assertEquals("three", reader.readLine())
        assertEquals("four", reader.readLine())
        assertEquals(null, reader.readLine())
    }

    @Test fun boundedLineReaderRejectsAnUnterminatedOversizedLine() {
        val reader = BoundedSseLineReader(StringReader("12345"), maxLineChars = 4)
        try { reader.readLine(); throw AssertionError("Expected oversized line error") }
        catch (error: IOException) { assertTrue(error.message!!.contains("oversized stream line")) }
    }

    @Test fun boundedLineReaderAcceptsTheConfiguredLimit() {
        val reader = BoundedSseLineReader(StringReader("1234\n"), maxLineChars = 4)
        assertEquals("1234", reader.readLine())
        assertEquals(null, reader.readLine())
    }

}
