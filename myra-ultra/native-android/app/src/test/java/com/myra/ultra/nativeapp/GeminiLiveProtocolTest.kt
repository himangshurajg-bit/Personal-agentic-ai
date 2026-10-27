package com.myra.ultra.nativeapp

import java.io.IOException
import org.json.JSONObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GeminiLiveProtocolTest {
    @Test fun setupEnablesAudioTranscriptionsAndOnlyTheTenNarrowLiveTools() {
        val setup = JSONObject(GeminiLiveProtocol.setupMessage("Be concise"))
            .getJSONObject("setup")
        assertEquals("models/${GeminiLiveProtocol.MODEL}", setup.getString("model"))
        assertEquals("AUDIO", setup.getJSONArray("responseModalities").getString(0))
        assertEquals("Aoede", setup.getJSONObject("speechConfig")
            .getJSONObject("voiceConfig").getJSONObject("prebuiltVoiceConfig").getString("voiceName"))
        assertTrue(setup.has("inputAudioTranscription"))
        assertTrue(setup.has("outputAudioTranscription"))
        val tools = setup.getJSONArray("tools")
        assertEquals(1, tools.length())
        val declarations = tools.getJSONObject(0).getJSONArray("functionDeclarations")
        assertEquals(10, declarations.length())
        assertEquals(listOf(GeminiLiveProtocol.BATTERY_STATUS_TOOL, GeminiLiveProtocol.SET_VOLUME_TOOL, GeminiLiveProtocol.SET_BRIGHTNESS_TOOL, GeminiLiveProtocol.SET_TIMER_TOOL, GeminiLiveProtocol.SET_ALARM_TOOL, GeminiLiveProtocol.NAVIGATE_TO_TOOL, GeminiLiveProtocol.TORCH_TOOL, GeminiLiveProtocol.SHOW_TOAST_TOOL, GeminiLiveProtocol.SHARE_LOCATION_TOOL, GeminiLiveProtocol.DOWNLOAD_FILE_TOOL),
            (0 until declarations.length()).map { declarations.getJSONObject(it).getString("name") })
        assertTrue(declarations.getJSONObject(0).getString("description").contains("read-only"))
        val volume = declarations.getJSONObject(1)
        assertTrue(volume.getJSONObject("parameters").getJSONArray("required").toString().contains("stream"))
        assertTrue(volume.getJSONObject("parameters").getJSONArray("required").toString().contains("percent"))
        val brightness = declarations.getJSONObject(2)
        assertTrue(brightness.getString("description").contains("own app window"))
        assertEquals("level", brightness.getJSONObject("parameters").getJSONArray("required").getString(0))
        val timer = declarations.getJSONObject(3)
        assertTrue(timer.getString("description").contains("24 hours"))
        assertTrue(timer.getJSONObject("parameters").getJSONArray("required").toString().contains("seconds"))
        val alarm = declarations.getJSONObject(4)
        assertTrue(alarm.getString("description").contains("exact 24-hour time"))
        assertTrue(alarm.getString("description").contains("native approval"))
        assertTrue(alarm.getJSONObject("parameters").getJSONArray("required").toString().contains("hour"))
        assertTrue(alarm.getJSONObject("parameters").getJSONArray("required").toString().contains("minute"))
        val navigation = declarations.getJSONObject(5)
        assertTrue(navigation.getString("description").contains("native approval"))
        assertTrue(navigation.getString("description").contains("does not start"))
        assertEquals("place", navigation.getJSONObject("parameters").getJSONArray("required").getString(0))
        val torch = declarations.getJSONObject(6)
        assertTrue(torch.getJSONObject("parameters").getJSONArray("required").toString().contains("on"))
        val toast = declarations.getJSONObject(7)
        assertTrue(toast.getString("description").contains("native approval"))
        assertEquals("text", toast.getJSONObject("parameters").getJSONArray("required").getString(0))
        val location = declarations.getJSONObject(8)
        assertTrue(location.getString("description").contains("coarse-location permission"))
        assertTrue(location.getString("description").contains("native review"))
        assertEquals(0, location.getJSONObject("parameters").getJSONObject("properties").length())
        val download = declarations.getJSONObject(9)
        assertTrue(download.getString("description").contains("native approval"))
        assertTrue(download.getString("description").contains("completion is not verified"))
        assertEquals("url", download.getJSONObject("parameters").getJSONArray("required").getString(0))
        assertEquals("Be concise", setup.getJSONObject("systemInstruction")
            .getJSONArray("parts").getJSONObject(0).getString("text"))
    }

    @Test fun brightnessLiveToolRequiresOneIntegerLevelInRange() {
        val call = GeminiLiveToolCall("b1", GeminiLiveProtocol.SET_BRIGHTNESS_TOOL, JSONObject().put("level", 128))
        assertTrue(GeminiLiveProtocol.toolResponseMessage(call, "ok").contains(GeminiLiveProtocol.SET_BRIGHTNESS_TOOL))
        assertThrowsIOException { GeminiLiveProtocol.toolResponseMessage(call.copy(args = JSONObject().put("level", 256)), "ok") }
        assertThrowsIOException { GeminiLiveProtocol.toolResponseMessage(call.copy(args = JSONObject().put("level", 128).put("extra", true)), "ok") }
    }

    @Test fun setupAlwaysIncludesResumptionConfigAndOnlyAddsSuppliedHandle() {
        val fresh = JSONObject(GeminiLiveProtocol.setupMessage("Be concise"))
            .getJSONObject("setup").getJSONObject("sessionResumption")
        assertEquals(0, fresh.length())

        val resumed = JSONObject(GeminiLiveProtocol.setupMessage("Be concise", "opaque-handle"))
            .getJSONObject("setup").getJSONObject("sessionResumption")
        assertEquals("opaque-handle", resumed.getString("handle"))
        assertThrowsIOException { GeminiLiveProtocol.setupMessage("Be concise", "bad\nhandle") }
        assertThrowsIOException {
            GeminiLiveProtocol.setupMessage("Be concise", "h".repeat(GeminiLiveProtocol.MAX_SESSION_HANDLE_CHARS + 1))
        }
    }

    @Test fun parsesResumptionUpdatesAndGoAwayDurationWithoutLosingEitherEvent() {
        val events = GeminiLiveProtocol.parseServerMessage(
            """{"sessionResumptionUpdate":{"resumable":true,"newHandle":"opaque"},"goAway":{"timeLeft":"30.5s"}}"""
        )
        assertEquals(GeminiLiveEvent.SessionResumptionUpdate(true, "opaque"), events[0])
        assertEquals(GeminiLiveEvent.GoAway(30_500L), events[1])
        assertEquals(GeminiLiveEvent.GoAway(120_000L),
            GeminiLiveProtocol.parseServerMessage("""{"goAway":{"timeLeft":"200s"}}""").single())
        assertEquals(GeminiLiveEvent.GoAway(0L),
            GeminiLiveProtocol.parseServerMessage("""{"goAway":{"timeLeft":"nonsense"}}""").single())
        val unsafe = GeminiLiveProtocol.parseServerMessage(
            """{"sessionResumptionUpdate":{"resumable":true,"newHandle":"line\nbreak"}}"""
        ).single() as GeminiLiveEvent.SessionResumptionUpdate
        assertTrue(unsafe.resumable)
        assertNull(unsafe.newHandle)
    }

    @Test fun pcmIsLittleEndianAndAudioMessageCarriesRate() {
        val pcm = GeminiLiveProtocol.pcm16LittleEndian(shortArrayOf(0x1234, -2), 2)
        assertArrayEquals(byteArrayOf(0x34, 0x12, 0xfe.toByte(), 0xff.toByte()), pcm)
        val audio = JSONObject(GeminiLiveProtocol.audioMessage(pcm))
            .getJSONObject("realtimeInput").getJSONObject("audio")
        assertEquals("audio/pcm;rate=16000", audio.getString("mimeType"))
        assertArrayEquals(pcm, java.util.Base64.getDecoder().decode(audio.getString("data")))
    }

    @Test fun parsesTranscriptAudioAndTurnLifecycle() {
        val wireAudio = java.util.Base64.getEncoder().encodeToString(byteArrayOf(1, 0, 2, 0))
        val events = GeminiLiveProtocol.parseServerMessage("""
            {"serverContent":{"inputTranscription":{"text":"hello"},"outputTranscription":{"text":"hi"},"modelTurn":{"parts":[{"inlineData":{"mimeType":"audio/pcm;rate=24000","data":"$wireAudio"}}]},"turnComplete":true}}
        """.trimIndent())
        assertEquals(GeminiLiveEvent.InputTranscript("hello"), events[0])
        assertEquals(GeminiLiveEvent.OutputTranscript("hi"), events[1])
        assertArrayEquals(byteArrayOf(1, 0, 2, 0), (events[2] as GeminiLiveEvent.Audio).pcm)
        assertEquals(GeminiLiveEvent.TurnComplete, events[3])
        assertEquals(listOf(GeminiLiveEvent.SetupComplete), GeminiLiveProtocol.parseServerMessage("{\"setupComplete\":{}}"))
        assertEquals(listOf(GeminiLiveEvent.Interrupted), GeminiLiveProtocol.parseServerMessage("{\"serverContent\":{\"interrupted\":true}}"))
    }


    @Test fun parsesNavigationRequestAndRejectsUnexpectedArguments() {
        val call = (GeminiLiveProtocol.parseServerMessage(
            """{"toolCall":{"functionCalls":[{"id":"nav-1","name":"navigate_to","args":{"place":"Guwahati Railway Station"}}]}}"""
        ).single() as GeminiLiveEvent.ToolCall).call
        val request = GeminiSafeTools.navigateRequest(call.args)
        assertEquals("Guwahati Railway Station", request.place)
        val response = JSONObject(GeminiLiveProtocol.toolResponseMessage(call, "Opened Maps search"))
            .getJSONObject("toolResponse").getJSONArray("functionResponses").getJSONObject(0)
        assertEquals("nav-1", response.getString("id"))
        assertEquals(GeminiLiveProtocol.NAVIGATE_TO_TOOL, response.getString("name"))
        assertThrowsIOException {
            GeminiLiveProtocol.parseServerMessage("""{"toolCall":{"functionCalls":[{"id":"nav-2","name":"navigate_to","args":{"place":"Guwahati","mode":"drive"}}]}}""")
        }
        assertThrowsIOException {
            GeminiLiveProtocol.toolResponseMessage(GeminiLiveToolCall("nav-3", GeminiLiveProtocol.NAVIGATE_TO_TOOL, JSONObject().put("place", "Guwahati").put("extra", true)), "ignored")
        }
    }

    @Test fun parsesReviewedDownloadCallAndRejectsUnexpectedArguments() {
        val call = (GeminiLiveProtocol.parseServerMessage(
            """{"toolCall":{"functionCalls":[{"id":"download-1","name":"download_file","args":{"url":"https://example.test/report.pdf"}}]}}"""
        ).single() as GeminiLiveEvent.ToolCall).call
        val request = GeminiDownloadPolicy.request(call.args)
        assertEquals("https://example.test/report.pdf", request.url)
        assertEquals("report.pdf", request.fileName)
        val response = JSONObject(GeminiLiveProtocol.toolResponseMessage(call, "Android accepted the download"))
            .getJSONObject("toolResponse").getJSONArray("functionResponses").getJSONObject(0)
        assertEquals("download-1", response.getString("id"))
        assertEquals(GeminiLiveProtocol.DOWNLOAD_FILE_TOOL, response.getString("name"))
        assertThrowsIOException {
            GeminiLiveProtocol.parseServerMessage("""{"toolCall":{"functionCalls":[{"id":"download-2","name":"download_file","args":{"url":"https://example.test/a.pdf","path":"/tmp/a.pdf"}}]}}""")
        }
        assertThrowsIOException {
            GeminiLiveProtocol.toolResponseMessage(GeminiLiveToolCall("download-3", GeminiLiveProtocol.DOWNLOAD_FILE_TOOL, JSONObject().put("url", "https://example.test/a.pdf").put("extra", true)), "ignored")
        }
    }

    @Test fun parsesOneBatteryFunctionCallAndEncodesMatchingFunctionResponse() {
        val events = GeminiLiveProtocol.parseServerMessage("""{"toolCall":{"functionCalls":[{"id":"call-9","name":"battery_status","args":{}}]}}""")
        val call = (events.single() as GeminiLiveEvent.ToolCall).call
        assertEquals("call-9", call.id)
        assertEquals(GeminiLiveProtocol.BATTERY_STATUS_TOOL, call.name)
        assertEquals(0, call.args.length())
        val response = JSONObject(GeminiLiveProtocol.toolResponseMessage(call, "82% · charging or full"))
            .getJSONObject("toolResponse").getJSONArray("functionResponses").getJSONObject(0)
        assertEquals("call-9", response.getString("id"))
        assertEquals(GeminiLiveProtocol.BATTERY_STATUS_TOOL, response.getString("name"))
        assertEquals("82% · charging or full", response.getJSONObject("response").getString("result"))
    }

    @Test fun parsesReviewedTimerCallAndRejectsUnexpectedArguments() {
        val call = (GeminiLiveProtocol.parseServerMessage(
            """{"toolCall":{"functionCalls":[{"id":"timer-1","name":"set_timer","args":{"seconds":300}}]}}"""
        ).single() as GeminiLiveEvent.ToolCall).call
        assertEquals(GeminiLiveProtocol.SET_TIMER_TOOL, call.name)
        assertEquals(300, GeminiTimerPolicy.request(call.args)!!.seconds)
        val response = JSONObject(GeminiLiveProtocol.toolResponseMessage(call, "Opened Clock"))
            .getJSONObject("toolResponse").getJSONArray("functionResponses").getJSONObject(0)
        assertEquals("timer-1", response.getString("id"))
        assertEquals(GeminiLiveProtocol.SET_TIMER_TOOL, response.getString("name"))
        assertThrowsIOException {
            GeminiLiveProtocol.parseServerMessage("""{"toolCall":{"functionCalls":[{"id":"timer-2","name":"set_timer","args":{"seconds":300,"label":"extra"}}]}}""")
        }
        assertThrowsIOException {
            GeminiLiveProtocol.toolResponseMessage(GeminiLiveToolCall("timer-3", GeminiLiveProtocol.SET_TIMER_TOOL, JSONObject().put("seconds", 300).put("extra", true)), "ignored")
        }
    }

    @Test fun parsesReviewedAlarmCallAndRejectsUnexpectedArguments() {
        val call = (GeminiLiveProtocol.parseServerMessage(
            """{"toolCall":{"functionCalls":[{"id":"alarm-1","name":"set_alarm","args":{"hour":7,"minute":30}}]}}"""
        ).single() as GeminiLiveEvent.ToolCall).call
        assertEquals(GeminiLiveProtocol.SET_ALARM_TOOL, call.name)
        val request = GeminiAlarmPolicy.request(call.args)!!
        assertEquals(7, request.hour)
        assertEquals(30, request.minute)
        val response = JSONObject(GeminiLiveProtocol.toolResponseMessage(call, "Opened Clock for approval"))
            .getJSONObject("toolResponse").getJSONArray("functionResponses").getJSONObject(0)
        assertEquals("alarm-1", response.getString("id"))
        assertEquals(GeminiLiveProtocol.SET_ALARM_TOOL, response.getString("name"))
        assertThrowsIOException {
            GeminiLiveProtocol.parseServerMessage("""{"toolCall":{"functionCalls":[{"id":"alarm-2","name":"set_alarm","args":{"hour":7,"minute":30,"label":"extra"}}]}}""")
        }
        assertThrowsIOException {
            GeminiLiveProtocol.toolResponseMessage(GeminiLiveToolCall("alarm-3", GeminiLiveProtocol.SET_ALARM_TOOL, JSONObject().put("hour", 7).put("minute", 30).put("extra", true)), "ignored")
        }
    }

    @Test fun parsesOnlyNoArgumentCurrentLocationLiveCallAndResponse() {
        val call = (GeminiLiveProtocol.parseServerMessage(
            """{"toolCall":{"functionCalls":[{"id":"loc-1","name":"get_current_location","args":{}}]}}"""
        ).single() as GeminiLiveEvent.ToolCall).call
        assertEquals(GeminiLiveProtocol.SHARE_LOCATION_TOOL, call.name)
        assertEquals(0, call.args.length())
        val response = JSONObject(GeminiLiveProtocol.toolResponseMessage(call, "approved approximate location"))
            .getJSONObject("toolResponse").getJSONArray("functionResponses").getJSONObject(0)
        assertEquals("loc-1", response.getString("id"))
        assertEquals(GeminiLiveProtocol.SHARE_LOCATION_TOOL, response.getString("name"))
        assertEquals("approved approximate location", response.getJSONObject("response").getString("result"))
        assertThrowsIOException {
            GeminiLiveProtocol.parseServerMessage("""{"toolCall":{"functionCalls":[{"id":"loc-2","name":"get_current_location","args":{"latitude":27.4}}]}}""")
        }
        assertThrowsIOException { GeminiLiveProtocol.toolResponseMessage(GeminiLiveToolCall("loc-3", GeminiLiveProtocol.SHARE_LOCATION_TOOL, JSONObject().put("extra", true)), "ignored") }
    }

    @Test fun parsesReviewedToastCallAndRejectsUnexpectedArguments() {
        val call = (GeminiLiveProtocol.parseServerMessage(
            """{"toolCall":{"functionCalls":[{"id":"toast-1","name":"show_toast","args":{"text":"Build complete"}}]}}"""
        ).single() as GeminiLiveEvent.ToolCall).call
        assertEquals(GeminiLiveProtocol.SHOW_TOAST_TOOL, call.name)
        assertEquals("Build complete", GeminiToastPolicy.request(call.args).text)
        val response = JSONObject(GeminiLiveProtocol.toolResponseMessage(call, "Displayed after approval"))
            .getJSONObject("toolResponse").getJSONArray("functionResponses").getJSONObject(0)
        assertEquals("toast-1", response.getString("id"))
        assertEquals(GeminiLiveProtocol.SHOW_TOAST_TOOL, response.getString("name"))
        assertThrowsIOException { GeminiLiveProtocol.parseServerMessage(
            """{"toolCall":{"functionCalls":[{"id":"toast-2","name":"show_toast","args":{"text":"x","extra":true}}]}}"""
        ) }
        assertThrowsIOException { GeminiLiveProtocol.toolResponseMessage(
            GeminiLiveToolCall("toast-3", GeminiLiveProtocol.SHOW_TOAST_TOOL, JSONObject()), "ignored"
        ) }
    }

    @Test fun parsesReviewedVolumeAndTorchCalls() {
        val volume = (GeminiLiveProtocol.parseServerMessage("""{"toolCall":{"functionCalls":[{"id":"v1","name":"set_volume","args":{"stream":"music","percent":50}}]}}""").single() as GeminiLiveEvent.ToolCall).call
        assertEquals(MyraVolumeStream.MUSIC, GeminiSafeTools.volumeRequest(volume.args).stream)
        assertEquals(50, GeminiSafeTools.volumeRequest(volume.args).percent)
        val torch = (GeminiLiveProtocol.parseServerMessage("""{"toolCall":{"functionCalls":[{"id":"t1","name":"torch","args":{"on":true}}]}}""").single() as GeminiLiveEvent.ToolCall).call
        assertTrue(GeminiSafeTools.torchRequest(torch.args).on)
        assertEquals("t1", JSONObject(GeminiLiveProtocol.toolResponseMessage(torch, "approved and applied"))
            .getJSONObject("toolResponse").getJSONArray("functionResponses").getJSONObject(0).getString("id"))
    }

    @Test fun rejectsUnsupportedMalformedOrMultipleLiveFunctionCalls() {
        assertThrowsIOException { GeminiLiveProtocol.parseServerMessage("{\"toolCall\":{}}") }
        assertThrowsIOException { GeminiLiveProtocol.parseServerMessage("""{"toolCall":{"functionCalls":[{"id":"x","name":"set_volume","args":{"stream":"music","percent":101}}]}}""") }
        assertThrowsIOException { GeminiLiveProtocol.parseServerMessage("""{"toolCall":{"functionCalls":[{"id":"x","name":"torch","args":{"on":true,"extra":1}}]}}""") }
        assertThrowsIOException { GeminiLiveProtocol.parseServerMessage("""{"toolCall":{"functionCalls":[{"id":"x","name":"battery_status","args":{"extra":true}}]}}""") }
        assertThrowsIOException { GeminiLiveProtocol.parseServerMessage("""{"toolCall":{"functionCalls":[{"id":"x","name":"battery_status","args":{}},{"id":"y","name":"battery_status","args":{}}]}}""") }
        assertThrowsIOException { GeminiLiveProtocol.toolResponseMessage(GeminiLiveToolCall("x", "torch", JSONObject()), "ignored") }
    }

    @Test fun ignoresUnrelatedEventsAndFailsClosedOnServerErrors() {
        assertTrue(GeminiLiveProtocol.parseServerMessage("{\"usageMetadata\":{}} ").isEmpty())
        assertThrowsIOException { GeminiLiveProtocol.parseServerMessage("{\"error\":{\"code\":403}}") }
    }

    @Test fun rejectsInvalidOrUnboundedAudioAndMessages() {
        assertThrowsIOException { GeminiLiveProtocol.audioMessage(byteArrayOf(1)) }
        assertThrowsIOException { GeminiLiveProtocol.audioMessage(ByteArray(GeminiLiveProtocol.MAX_AUDIO_BYTES + 2)) }
        assertThrowsIOException { GeminiLiveProtocol.pcm16LittleEndian(shortArrayOf(1), 2) }
        assertThrowsIOException { GeminiLiveProtocol.parseServerMessage("not json") }
        assertThrowsIOException { GeminiLiveProtocol.parseServerMessage(" ".repeat(GeminiLiveProtocol.MAX_MESSAGE_CHARS + 1)) }
        assertThrowsIOException {
            GeminiLiveProtocol.parseServerMessage("""{"serverContent":{"modelTurn":{"parts":[{"inlineData":{"mimeType":"audio/pcm","data":"AQ=="}}]}}}""")
        }
    }

    private fun assertThrowsIOException(block: () -> Unit) {
        try { block(); throw AssertionError("Expected IOException") } catch (_: IOException) { }
    }
}
