package com.myra.ultra.nativeapp

import java.io.IOException
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class GeminiSafeToolsTest {
    @Test fun contactLookupToolIsDeclaredAndRequiresExactNameOnly() {
        val declarations = GeminiSafeTools.declaration().getJSONArray("functionDeclarations")
        val contact = (0 until declarations.length()).map { declarations.getJSONObject(it) }
            .single { it.getString("name") == GeminiSafeTools.FIND_CONTACT }
        assertTrue(contact.getString("description").contains("system contact picker"))
        assertTrue(contact.getString("description").contains("separately approves"))
        assertEquals(GeminiSafeTools.FIND_CONTACT, GeminiSafeTools.validate(
            GeminiSafeTools.FIND_CONTACT, JSONObject().put("name", "Ada Lovelace"),
        ))
    }

    @Test fun acceptsReadOnlyBatteryCallWithNoArguments() {
        assertEquals(GeminiSafeTools.BATTERY_STATUS, GeminiSafeTools.validate("get_battery_status", JSONObject()))
    }

    @Test fun phoneVibrationUsesFixedShortPulseAndRejectsModelArguments() {
        val request = GeminiSafeTools.vibrationRequest(JSONObject())
        assertEquals(GeminiSafeTools.VIBRATION_MILLIS, request.durationMillis)
        assertEquals("one short pulse (80 ms)", request.displayText)
        assertEquals(GeminiSafeTools.VIBRATE_PHONE, GeminiSafeTools.validate(GeminiSafeTools.VIBRATE_PHONE, JSONObject()))
        listOf(JSONObject().put("duration", 500), JSONObject().put("amplitude", 255)).forEach { args ->
            expectRejected { GeminiSafeTools.validate(GeminiSafeTools.VIBRATE_PHONE, args) }
        }
        val declaration = GeminiSafeTools.declaration().getJSONArray("functionDeclarations")
            .getJSONObject(3)
        assertEquals(GeminiSafeTools.VIBRATE_PHONE, declaration.getString("name"))
        assertTrue(declaration.getString("description").contains("fixed 80 ms"))
        assertTrue(declaration.getString("description").contains("native confirmation"))
    }

    @Test fun phoneVibrationRequiresExplicitLatestUserRequest() {
        assertTrue(GeminiSafeTools.hasExplicitVibrationIntent("Vibrate my phone"))
        assertTrue(GeminiSafeTools.hasExplicitVibrationIntent("Please buzz the device once"))
        assertTrue(GeminiSafeTools.hasExplicitVibrationIntent("Can you make my phone vibrate?"))
        assertEquals(false, GeminiSafeTools.hasExplicitVibrationIntent("My phone vibrates too much"))
        assertEquals(false, GeminiSafeTools.hasExplicitVibrationIntent("Don't vibrate my phone"))
        assertEquals(false, GeminiSafeTools.hasExplicitVibrationIntent("I don't want you to buzz my device"))
        assertEquals(false, GeminiSafeTools.hasExplicitVibrationIntent("Make my alarm vibrate"))
        assertEquals(false, GeminiSafeTools.hasExplicitVibrationIntent("Vibrate"))
        assertEquals(false, GeminiSafeTools.hasExplicitVibrationIntent("Make my phone vibrate tomorrow"))
        assertEquals(false, GeminiSafeTools.hasExplicitVibrationIntent("Make my phone vibrate when the timer ends"))
    }

    @Test fun clipboardWriteRequiresBoundedPlainTextWithExactArguments() {
        val exact = "hello, world\nsecond line"
        assertEquals(exact, GeminiSafeTools.clipboardWriteRequest(JSONObject().put("text", exact)).text)
        assertEquals(GeminiSafeTools.COPY_CLIPBOARD, GeminiSafeTools.validate(GeminiSafeTools.COPY_CLIPBOARD, JSONObject().put("text", exact)))
        listOf(
            JSONObject(),
            JSONObject().put("text", " "),
            JSONObject().put("text", "bad\u0000text"),
            JSONObject().put("text", "x".repeat(4001)),
            JSONObject().put("text", "ok").put("extra", true),
            JSONObject().put("text", 123),
        ).forEach { args -> expectRejected { GeminiSafeTools.validate(GeminiSafeTools.COPY_CLIPBOARD, args) } }
    }

    @Test fun clipboardWriteRequiresExplicitLatestRequestAndExactUserText() {
        val text = "Bring the blue folder"
        assertTrue(GeminiSafeTools.hasExplicitClipboardWriteIntent("Copy $text to the clipboard", text))
        assertTrue(GeminiSafeTools.hasExplicitClipboardWriteIntent("Put $text on clipboard", text))
        assertEquals(false, GeminiSafeTools.hasExplicitClipboardWriteIntent("Copy a summary to clipboard", text))
        assertEquals(false, GeminiSafeTools.hasExplicitClipboardWriteIntent("Don't copy $text to clipboard", text))
        assertEquals(false, GeminiSafeTools.hasExplicitClipboardWriteIntent("Could you remember $text?", text))
    }

    @Test fun brightnessRequestRequiresOneExactIntegerFromZeroThrough255() {
        assertEquals(0, GeminiSafeTools.brightnessRequest(JSONObject().put("level", 0)).level)
        assertEquals(255, GeminiSafeTools.brightnessRequest(JSONObject().put("level", 255)).level)
        assertEquals(128, GeminiSafeTools.brightnessRequest(JSONObject().put("level", 128)).level)
        listOf(
            JSONObject(),
            JSONObject().put("level", -1),
            JSONObject().put("level", 256),
            JSONObject().put("level", 12.5),
            JSONObject().put("level", "128"),
            JSONObject().put("level", 128).put("extra", true),
        ).forEach { args -> expectRejected { GeminiSafeTools.validate(GeminiSafeTools.SET_BRIGHTNESS, args) } }
    }

    @Test fun brightnessToolDeclarationIsWindowScopedAndRequiresApproval() {
        val declarations = GeminiSafeTools.declaration().getJSONArray("functionDeclarations")
        val brightness = (0 until declarations.length()).map { declarations.getJSONObject(it) }
            .single { it.getString("name") == GeminiSafeTools.SET_BRIGHTNESS }
        assertTrue(brightness.getString("description").contains("never changes device-wide brightness"))
        assertTrue(brightness.getString("description").contains("approval"))
        val level = brightness.getJSONObject("parameters").getJSONObject("properties").getJSONObject("level")
        assertEquals("INTEGER", level.getString("type"))
        assertEquals(0, level.getInt("minimum"))
        assertEquals(255, level.getInt("maximum"))
    }

    @Test fun brightnessChangeRequiresExactLatestExplicitLevelAndRejectsAmbiguity() {
        assertTrue(GeminiSafeTools.hasExplicitBrightnessIntent("Set screen brightness to 128", 128))
        assertTrue(GeminiSafeTools.hasExplicitBrightnessIntent("Please adjust display brightness to 0", 0))
        assertTrue(GeminiSafeTools.hasExplicitBrightnessIntent("Change brightness to 255", 255))
        assertEquals(false, GeminiSafeTools.hasExplicitBrightnessIntent("What is my screen brightness?", 128))
        assertEquals(false, GeminiSafeTools.hasExplicitBrightnessIntent("Set screen brightness to 50", 128))
        assertEquals(false, GeminiSafeTools.hasExplicitBrightnessIntent("Set screen brightness to 50%", 50))
        assertEquals(false, GeminiSafeTools.hasExplicitBrightnessIntent("Don't set screen brightness to 128", 128))
        assertEquals(false, GeminiSafeTools.hasExplicitBrightnessIntent("Set brightness to 128 or 180", 128))
        assertEquals(false, GeminiSafeTools.hasExplicitBrightnessIntent("Set screen brightness to 256", 256))
        assertEquals(false, GeminiSafeTools.hasExplicitBrightnessIntent("Set screen brightness to 1000", 100))
        assertEquals(false, GeminiSafeTools.hasExplicitBrightnessIntent("Change wallpaper; my screen brightness is 128", 128))
    }

    @Test fun acceptsExactReviewedVolumeRequestAcrossSupportedStreams() {
        MyraVolumeStream.values().forEach { stream ->
            val args = JSONObject().put("stream", stream.key).put("percent", 50)
            assertEquals(GeminiSafeTools.SET_VOLUME, GeminiSafeTools.validate("set_volume", args))
            val request = GeminiSafeTools.volumeRequest(args)
            assertEquals(stream, request.stream)
            assertEquals(50, request.percent)
        }
    }

    @Test fun rejectsUnknownToolsAndUnexpectedBatteryArguments() {
        expectRejected { GeminiSafeTools.validate("get_battery_status", JSONObject().put("level", 100)) }
    }

    @Test fun volumeArgumentsMustBeExactAndBounded() {
        val valid = JSONObject().put("stream", "music").put("percent", 0)
        assertEquals(0, GeminiSafeTools.volumeRequest(valid).percent)
        assertEquals(100, GeminiSafeTools.volumeRequest(JSONObject().put("stream", "music").put("percent", 100)).percent)
        listOf(
            JSONObject(),
            JSONObject().put("stream", "music"),
            JSONObject().put("stream", "music").put("percent", 50).put("extra", true),
            JSONObject().put("stream", "voice").put("percent", 50),
            JSONObject().put("stream", "MUSIC").put("percent", 50),
            JSONObject().put("stream", "music").put("percent", -1),
            JSONObject().put("stream", "music").put("percent", 101),
            JSONObject().put("stream", "music").put("percent", 50.5),
            JSONObject().put("stream", "music").put("percent", "50"),
        ).forEach { args -> expectRejected { GeminiSafeTools.validate("set_volume", args) } }
    }

    @Test fun declarationsDescribeReadOnlyBatteryAndReviewedVolumeAction() {
        val declarations = GeminiSafeTools.declaration().getJSONArray("functionDeclarations")
        val battery = declarations.getJSONObject(0)
        assertEquals("get_battery_status", battery.getString("name"))
        assertTrue(battery.getString("description").contains("read-only"))
        assertEquals(0, battery.getJSONObject("parameters").getJSONObject("properties").length())
        val volume = declarations.getJSONObject(1)
        assertEquals("set_volume", volume.getString("name"))
        assertTrue(volume.getString("description").contains("will not apply it unless the user confirms"))
        val properties = volume.getJSONObject("parameters").getJSONObject("properties")
        assertEquals(6, properties.getJSONObject("stream").getJSONArray("enum").length())
        assertEquals(0, properties.getJSONObject("percent").getInt("minimum"))
        assertEquals(100, properties.getJSONObject("percent").getInt("maximum"))
    }

    @Test fun preservesModelCallEnvelopeAndEncodesFunctionResponse() {
        val args = JSONObject().put("stream", "music").put("percent", 50)
        val original = JSONObject().put("role", "model")
            .put("parts", JSONArray().put(JSONObject().put("functionCall", JSONObject()
                .put("name", "set_volume").put("args", args).put("id", "call-7"))))
            .put("thoughtSignature", "opaque")
        val callContent = GeminiSafeTools.originalModelContent("set_volume", args, original)
        assertEquals("call-7", callContent.getJSONArray("parts").getJSONObject(0).getJSONObject("functionCall").getString("id"))
        assertEquals("opaque", callContent.getString("thoughtSignature"))
        val response = GeminiSafeTools.functionResponsePart("set_volume", "Android now reports Music volume 5/10.", "call-7")
            .getJSONObject("functionResponse")
        assertEquals("set_volume", response.getString("name"))
        assertEquals("call-7", response.getString("id"))
        assertEquals("Android now reports Music volume 5/10.", response.getJSONObject("response").getString("result"))
    }


    @Test fun acceptsOnlyAnExactBooleanTorchRequest() {
        assertEquals(true, GeminiSafeTools.torchRequest(JSONObject().put("on", true)).on)
        assertEquals(false, GeminiSafeTools.torchRequest(JSONObject().put("on", false)).on)
        listOf(JSONObject(), JSONObject().put("on", "true"), JSONObject().put("on", 1),
            JSONObject().put("on", true).put("extra", false)).forEach { args ->
            expectRejected { GeminiSafeTools.validate("torch", args) }
        }
        expectRejected { GeminiSafeTools.validate("torch", JSONObject().put("on", true).put("extra", 1)) }
    }

    @Test fun torchRequiresLatestUserTextToNameLightAndRequestedDirection() {
        assertTrue(GeminiSafeTools.hasExplicitTorchIntent("Please turn the flashlight on", true))
        assertTrue(GeminiSafeTools.hasExplicitTorchIntent("switch torch off", false))
        assertEquals(false, GeminiSafeTools.hasExplicitTorchIntent("turn the flashlight off", true))
        assertEquals(false, GeminiSafeTools.hasExplicitTorchIntent("turn it on", true))
        assertEquals(false, GeminiSafeTools.hasExplicitTorchIntent("turn on music", true))
    }

    @Test fun declaresTorchAsReviewedExplicitBooleanAndPreservesExactCall() {
        val declarations = GeminiSafeTools.declaration().getJSONArray("functionDeclarations")
        val torch = declarations.getJSONObject(2)
        assertEquals("torch", torch.getString("name"))
        assertTrue(torch.getString("description").contains("only after Apply"))
        assertEquals("BOOLEAN", torch.getJSONObject("parameters").getJSONObject("properties").getJSONObject("on").getString("type"))
        val args = JSONObject().put("on", true)
        val original = JSONObject().put("role", "model").put("parts", JSONArray().put(JSONObject()
            .put("functionCall", JSONObject().put("name", "torch").put("args", args))))
        assertEquals("model", GeminiSafeTools.originalModelContent("torch", args, original).getString("role"))
        expectRejected { GeminiSafeTools.originalModelContent("torch", JSONObject().put("on", false), original) }
    }

    @Test fun wifiReadReportsOnlyNonIdentifyingStateAndRequiresExplicitLatestQuestion() {
        val connected = GeminiSafeTools.wifiStatusResult(WifiStatusSnapshot(true, true, -54))
        assertTrue(connected.contains("enabled"))
        assertTrue(connected.contains("active Wi-Fi connection"))
        assertTrue(connected.contains("-54 dBm"))
        assertTrue(connected.contains("No SSID, BSSID, or IP address was read"))
        assertTrue(GeminiSafeTools.wifiStatusResult(WifiStatusSnapshot(false, null, null)).contains("disabled"))
        assertTrue(GeminiSafeTools.wifiStatusResult(WifiStatusSnapshot(true, false, null)).contains("no active Wi-Fi connection"))
        assertTrue(GeminiSafeTools.hasExplicitWifiStatusIntent("Is Wi-Fi on?"))
        assertTrue(GeminiSafeTools.hasExplicitWifiStatusIntent("Check the WiFi status"))
        assertTrue(GeminiSafeTools.hasExplicitWifiStatusIntent("Is Wi-Fi connected?"))
        assertTrue(GeminiSafeTools.hasExplicitWifiStatusIntent("How is the Wi-Fi signal?"))
        assertEquals(false, GeminiSafeTools.hasExplicitWifiStatusIntent("What is Wi-Fi?"))
        assertEquals(false, GeminiSafeTools.hasExplicitWifiStatusIntent("Tell me about Wi-Fi signal processing"))
    }

    @Test fun wifiSetRequiresLatestExplicitWifiRequestAndMatchingDirection() {
        assertTrue(GeminiSafeTools.hasExplicitWifiIntent("Please turn Wi-Fi on", true))
        assertTrue(GeminiSafeTools.hasExplicitWifiIntent("Disable wifi", false))
        assertTrue(GeminiSafeTools.hasExplicitWifiIntent("Switch off the wireless", false))
        assertEquals(false, GeminiSafeTools.hasExplicitWifiIntent("My Wi-Fi is off", false))
        assertEquals(false, GeminiSafeTools.hasExplicitWifiIntent("Turn Wi-Fi off", true))
        assertEquals(false, GeminiSafeTools.hasExplicitWifiIntent("Don't turn Wi-Fi on", true))
        assertEquals(false, GeminiSafeTools.hasExplicitWifiIntent("Turn Bluetooth on", true))
    }

    @Test fun wifiSettingsRequestAndIntentConstructionNeverToggleDirectly() {
        assertEquals(false, GeminiSafeTools.wifiSetRequest(JSONObject().put("on", false)).on)
        assertEquals(true, GeminiSafeTools.wifiSetRequest(JSONObject().put("on", true)).on)
        expectRejected { GeminiSafeTools.validate(GeminiSafeTools.WIFI_SET, JSONObject().put("on", "true")) }
        expectRejected { GeminiSafeTools.validate(GeminiSafeTools.WIFI_SET, JSONObject().put("on", true).put("extra", 1)) }
        val settings = GeminiSafeTools.wifiSettingsIntents()
        assertEquals("android.settings.panel.action.INTERNET_CONNECTIVITY", settings.primaryAction)
        assertEquals("android.settings.WIFI_SETTINGS", settings.fallbackAction)
        val declarations = GeminiSafeTools.declaration().getJSONArray("functionDeclarations")
        val status = declarations.getJSONObject(7)
        assertEquals(GeminiSafeTools.WIFI_STATUS, status.getString("name"))
        assertTrue(status.getString("description").contains("RSSI"))
        assertTrue(status.getString("description").contains("Never read SSID"))
        assertTrue(status.getString("description").contains("do not request location permission"))
        val set = declarations.getJSONObject(8)
        assertEquals(GeminiSafeTools.WIFI_SET, set.getString("name"))
        assertTrue(set.getString("description").contains("never toggles Wi-Fi"))
        expectRejected { GeminiSafeTools.validate(GeminiSafeTools.WIFI_STATUS, JSONObject().put("ssid", "private")) }
    }

    @Test fun smsDraftValidatesExactPhoneAndBoundedNonemptyBody() {
        val args = JSONObject().put("number", "+1 (415) 555-0137").put("message", "Hi!\nAre we still on for 6?")
        assertEquals(GeminiSafeTools.SMS_DRAFT, GeminiSafeTools.validate("send_sms_draft", args))
        val request = GeminiSafeTools.smsDraftRequest(args)
        assertEquals("+14155550137", request.number)
        assertEquals("Hi!\nAre we still on for 6?", request.body)
        listOf(
            JSONObject(),
            JSONObject().put("number", "4155550137"),
            JSONObject().put("number", "+14155550137").put("message", " "),
            JSONObject().put("number", "+14155550137").put("message", "x".repeat(1601)),
            JSONObject().put("number", "call 4155550137").put("message", "hello"),
            JSONObject().put("number", "+1415550137").put("message", "hello").put("extra", true),
        ).forEach { args -> expectRejected { GeminiSafeTools.validate("send_sms_draft", args) } }
        expectRejected { GeminiSafeTools.validate("send_sms_draft", JSONObject().put("number", "1234567").put("message", "bad\u0001text")) }
    }

    @Test fun smsRequiresExplicitLatestSendRequestAndSameNumber() {
        val number = "+14155550137"
        assertEquals(true, GeminiSafeTools.hasExplicitSmsIntent("Please send an SMS to +1 (415) 555-0137 saying hello", number))
        assertEquals(false, GeminiSafeTools.hasExplicitSmsIntent("What is an SMS? +1 (415) 555-0137", number))
        assertEquals(false, GeminiSafeTools.hasExplicitSmsIntent("Don't send an SMS to +1 (415) 555-0137", number))
        assertEquals(false, GeminiSafeTools.hasExplicitSmsIntent("Send an SMS to 4155550199", number))
        assertEquals(false, GeminiSafeTools.hasExplicitSmsIntent("Send an SMS to a contact", number))
    }

    @Test fun smsComposerIntentUsesExactReviewedRecipientAndBodyWithoutSending() {
        val request = GeminiSafeTools.smsDraftRequest(JSONObject()
            .put("number", "+91 98765-43210")
            .put("message", "Exact draft\nSecond line"))
        val intent = GeminiSafeTools.smsDraftIntent(request)
        assertEquals("android.intent.action.SENDTO", intent.action)
        assertEquals("smsto:+919876543210", intent.data)
        assertEquals("Exact draft\nSecond line", intent.bodyExtra)
        val declarations = GeminiSafeTools.declaration().getJSONArray("functionDeclarations")
        val sms = declarations.getJSONObject(4)
        assertEquals("send_sms_draft", sms.getString("name"))
        assertTrue(sms.getString("description").contains("it never sends"))
        val original = JSONObject().put("role", "model").put("parts", JSONArray().put(JSONObject()
            .put("functionCall", JSONObject().put("name", "send_sms_draft").put("args", JSONObject()
                .put("number", "+91 98765-43210").put("message", "Exact draft\nSecond line")))))
        assertEquals("model", GeminiSafeTools.originalModelContent("send_sms_draft", JSONObject()
            .put("number", "+91 98765-43210").put("message", "Exact draft\nSecond line"), original).getString("role"))
        expectRejected { GeminiSafeTools.originalModelContent("send_sms_draft", JSONObject()
            .put("number", "+919876543210").put("message", "changed"), original) }
    }

    @Test fun whatsappDraftRequiresExactInternationalNumberAndBoundedMessage() {
        val args = JSONObject().put("number", "+1 (415) 555-0137").put("message", "Hi + welcome?\nAre we still on?")
        assertEquals(GeminiSafeTools.WHATSAPP_DRAFT, GeminiSafeTools.validate(GeminiSafeTools.WHATSAPP_DRAFT, args))
        val request = GeminiSafeTools.whatsappDraftRequest(args)
        assertEquals("+14155550137", request.number)
        assertEquals("Hi + welcome?\nAre we still on?", request.message)
        listOf(
            JSONObject(),
            JSONObject().put("number", "+1 (415) 555-0137"),
            JSONObject().put("number", "1234567").put("message", "hello"),
            JSONObject().put("number", "0123456789").put("message", "hello"),
            JSONObject().put("number", "+12345678").put("message", " "),
            JSONObject().put("number", "+12345678").put("message", "x".repeat(1601)),
            JSONObject().put("number", "+12345678").put("message", "bad\u0001text"),
            JSONObject().put("number", "+12345678").put("message", "hello").put("extra", true),
        ).forEach { invalid -> expectRejected { GeminiSafeTools.validate(GeminiSafeTools.WHATSAPP_DRAFT, invalid) } }
    }

    @Test fun whatsappHandoffRequiresLatestExplicitRequestAndOneMatchingInternationalNumber() {
        val number = "+14155550137"
        assertTrue(GeminiSafeTools.hasExplicitWhatsappIntent("Please send a WhatsApp message to +1 (415) 555-0137 saying hello", number))
        assertTrue(GeminiSafeTools.hasExplicitWhatsappIntent("Can you send this on WhatsApp to +1 415 555 0137?", number))
        assertEquals(false, GeminiSafeTools.hasExplicitWhatsappIntent("Open WhatsApp for +1 (415) 555-0137", number))
        assertEquals(false, GeminiSafeTools.hasExplicitWhatsappIntent("Please send an SMS to +1 (415) 555-0137", number))
        assertEquals(false, GeminiSafeTools.hasExplicitWhatsappIntent("Don't send a WhatsApp message to +1 (415) 555-0137", number))
        assertEquals(false, GeminiSafeTools.hasExplicitWhatsappIntent("Send a WhatsApp message to +1 415 555 0199", number))
        assertEquals(false, GeminiSafeTools.hasExplicitWhatsappIntent("Send a WhatsApp message to +1 415 555 0137 or +1 415 555 0199", number))
        assertEquals(false, GeminiSafeTools.hasExplicitWhatsappIntent("Send a WhatsApp message to a contact", number))
    }

    @Test fun whatsappIntentPrefillsExactMessageInViewLinkAndNeverSends() {
        val request = GeminiSafeTools.whatsappDraftRequest(JSONObject()
            .put("number", "+91 98765-43210")
            .put("message", "Exact + draft?"))
        val intent = GeminiSafeTools.whatsappDraftIntent(request)
        assertEquals("android.intent.action.VIEW", intent.action)
        assertEquals("https://wa.me/919876543210?text=Exact+%2B+draft%3F", intent.data)
        val declaration = GeminiSafeTools.declaration().getJSONArray("functionDeclarations").getJSONObject(6)
        assertEquals(GeminiSafeTools.WHATSAPP_DRAFT, declaration.getString("name"))
        assertTrue(declaration.getString("description").contains("never sends"))
        val props = declaration.getJSONObject("parameters").getJSONObject("properties")
        assertEquals("STRING", props.getJSONObject("number").getString("type"))
        assertEquals("STRING", props.getJSONObject("message").getString("type"))
    }

    @Test fun callHandoffRequiresExplicitLatestRequestAndOneExactNumber() {
        val number = "+919876543210"
        assertTrue(GeminiSafeTools.hasExplicitDialIntent("Please call this number +91 98765-43210", number))
        assertTrue(GeminiSafeTools.hasExplicitDialIntent("Call +91 98765-43210", number))
        assertTrue(GeminiSafeTools.hasExplicitDialIntent("Could you call +91 98765-43210?", number))
        assertEquals(false, GeminiSafeTools.hasExplicitDialIntent("What is this number +91 98765-43210?", number))
        assertEquals(false, GeminiSafeTools.hasExplicitDialIntent("Don't call +91 98765-43210", number))
        assertEquals(false, GeminiSafeTools.hasExplicitDialIntent("Call +91 98765-43210 or +91 99999-00000", number))
        assertEquals(false, GeminiSafeTools.hasExplicitDialIntent("Call +91 99999-00000", number))
        assertEquals(false, GeminiSafeTools.hasExplicitDialIntent("Call a contact", number))
    }

    @Test fun dialToolRequiresExactValidNumberAndConstructsDialOnlyIntent() {
        val request = GeminiSafeTools.dialRequest(JSONObject().put("number", "+91 (98765) 43210"))
        assertEquals("+919876543210", request.number)
        val intent = GeminiSafeTools.dialIntent(request)
        assertEquals("android.intent.action.DIAL", intent.action)
        assertEquals("tel:+919876543210", intent.data)
        listOf(JSONObject(), JSONObject().put("number", "1234567").put("extra", true),
            JSONObject().put("number", "call 9876543210"), JSONObject().put("number", "++919876543210"),
            JSONObject().put("number", "123456")).forEach { args ->
            expectRejected { GeminiSafeTools.validate(GeminiSafeTools.DIAL_PHONE, args) }
        }
        val declarations = GeminiSafeTools.declaration().getJSONArray("functionDeclarations")
        val call = declarations.getJSONObject(5)
        assertEquals(GeminiSafeTools.DIAL_PHONE, call.getString("name"))
        assertTrue(call.getString("description").contains("never places a call"))
        assertTrue(call.getString("description").contains("exact phone number"))
    }

    @Test fun webLinkRequiresOneSafeExactLatestUserSuppliedUrlAndReviewIntent() {
        val url = "https://example.com/a?x=1&y=two"
        val args = JSONObject().put("url", url)
        assertEquals(GeminiSafeTools.OPEN_URL, GeminiSafeTools.validate(GeminiSafeTools.OPEN_URL, args))
        assertEquals(GeminiOpenUrlRequest(url), GeminiSafeTools.openUrlRequest(args))
        val intent = GeminiSafeTools.openUrlIntent(GeminiOpenUrlRequest(url))
        assertEquals("android.intent.action.VIEW", intent.action)
        assertEquals(url, intent.data)

        assertTrue(GeminiSafeTools.hasExplicitOpenUrlIntent("Please open $url", url))
        assertTrue(GeminiSafeTools.hasExplicitOpenUrlIntent("Visit $url.", url))
        assertEquals(false, GeminiSafeTools.hasExplicitOpenUrlIntent("What is on $url?", url))
        assertEquals(false, GeminiSafeTools.hasExplicitOpenUrlIntent("Do not open $url", url))
        assertEquals(false, GeminiSafeTools.hasExplicitOpenUrlIntent("Open https://different.example", url))
        assertEquals(false, GeminiSafeTools.hasExplicitOpenUrlIntent("Open $url and https://other.example", url))

        listOf(
            JSONObject(),
            JSONObject().put("url", url).put("extra", "ignored"),
            JSONObject().put("url", "javascript:alert(1)"),
            JSONObject().put("url", "file:///etc/passwd"),
            JSONObject().put("url", "https://user:password@example.com/"),
            JSONObject().put("url", "https://example.com/ with-space"),
            JSONObject().put("url", "https://example.com/").put("x", 1),
        ).forEach { bad -> expectRejected { GeminiSafeTools.validate(GeminiSafeTools.OPEN_URL, bad) } }
        assertEquals(false, GeminiSafeTools.hasExplicitOpenUrlIntent("Open https://user:pass@example.com", "https://user:pass@example.com"))
    }

    private fun expectRejected(block: () -> Unit) {
        try { block(); throw AssertionError("Expected rejection") }
        catch (error: IOException) { assertTrue(error.message!!.isNotBlank()) }
    }
}
