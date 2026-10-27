package com.myra.ultra.nativeapp

import java.io.IOException
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AppLaunchTest {
    @Test fun onlyCuratedAppKeysAreAcceptedWithExactArguments() {
        val request = AppLaunchPolicy.request(JSONObject().put("app", "spotify"))
        assertEquals(SupportedLaunchApp.SPOTIFY, request.app)
        assertEquals("Spotify", request.displayName)
        assertEquals("com.spotify.music", request.app.packageName)
        listOf(
            JSONObject(),
            JSONObject().put("app", "com.whatsapp"),
            JSONObject().put("app", "arbitrary_app"),
            JSONObject().put("app", "SPOTIFY"),
            JSONObject().put("app", "spotify").put("package", "com.example.other"),
            JSONObject().put("app", 1),
        ).forEach { args ->
            try {
                AppLaunchPolicy.request(args)
                throw AssertionError("Expected invalid app-launch request to fail")
            } catch (_: IOException) { }
        }
    }

    @Test fun latestMessageMustExplicitlyAskForTheExactSingleSupportedApp() {
        assertTrue(AppLaunchPolicy.hasExplicitIntent("Please open Spotify", SupportedLaunchApp.SPOTIFY))
        assertTrue(AppLaunchPolicy.hasExplicitIntent("Can you launch Google Maps?", SupportedLaunchApp.MAPS))
        assertTrue(AppLaunchPolicy.hasExplicitIntent("start Chrome", SupportedLaunchApp.CHROME))
        assertFalse(AppLaunchPolicy.hasExplicitIntent("What is Spotify?", SupportedLaunchApp.SPOTIFY))
        assertFalse(AppLaunchPolicy.hasExplicitIntent("Don't open Spotify", SupportedLaunchApp.SPOTIFY))
        assertFalse(AppLaunchPolicy.hasExplicitIntent("Open Spotify", SupportedLaunchApp.CHROME))
        assertFalse(AppLaunchPolicy.hasExplicitIntent("Open Spotify and Chrome", SupportedLaunchApp.SPOTIFY))
        assertFalse(AppLaunchPolicy.hasExplicitIntent("Open Google Maps", SupportedLaunchApp.CHROME))
        assertFalse(AppLaunchPolicy.hasExplicitIntent("Open Maps settings", SupportedLaunchApp.MAPS))
    }


    @Test fun prototypeBackedAppsResolveOnlyByExplicitExactNames() {
        val examples = listOf(
            "whatsapp" to SupportedLaunchApp.WHATSAPP,
            "whatsapp_business" to SupportedLaunchApp.WHATSAPP_BUSINESS,
            "instagram" to SupportedLaunchApp.INSTAGRAM,
            "youtube_music" to SupportedLaunchApp.YOUTUBE_MUSIC,
            "photos" to SupportedLaunchApp.PHOTOS,
            "messages" to SupportedLaunchApp.MESSAGES,
            "telegram" to SupportedLaunchApp.TELEGRAM,
            "calendar" to SupportedLaunchApp.CALENDAR,
            "drive" to SupportedLaunchApp.DRIVE,
            "play_store" to SupportedLaunchApp.PLAY_STORE,
            "phone" to SupportedLaunchApp.PHONE,
            "contacts" to SupportedLaunchApp.CONTACTS,
            "facebook" to SupportedLaunchApp.FACEBOOK,
            "linkedin" to SupportedLaunchApp.LINKEDIN,
            "amazon" to SupportedLaunchApp.AMAZON,
            "chatgpt" to SupportedLaunchApp.CHATGPT,
            "flipkart" to SupportedLaunchApp.FLIPKART,
            "gemini" to SupportedLaunchApp.GEMINI,
            "google_meet" to SupportedLaunchApp.GOOGLE_MEET,
            "messenger" to SupportedLaunchApp.MESSENGER,
            "netflix" to SupportedLaunchApp.NETFLIX,
            "ola" to SupportedLaunchApp.OLA,
            "snapchat" to SupportedLaunchApp.SNAPCHAT,
            "swiggy" to SupportedLaunchApp.SWIGGY,
            "uber" to SupportedLaunchApp.UBER,
            "x_app" to SupportedLaunchApp.X_APP,
            "zomato" to SupportedLaunchApp.ZOMATO,
            "zoom" to SupportedLaunchApp.ZOOM,
        )
        examples.forEach { (key, app) ->
            assertEquals(app, AppLaunchPolicy.request(JSONObject().put("app", key)).app)
            assertTrue(AppLaunchPolicy.hasExplicitIntent("Please open ${app.displayName}", app))
            assertFalse(AppLaunchPolicy.hasExplicitIntent("Tell me about ${app.displayName}", app))
        }
        assertFalse(AppLaunchPolicy.hasExplicitIntent("Open WhatsApp Business", SupportedLaunchApp.WHATSAPP))
        assertTrue(AppLaunchPolicy.hasExplicitIntent("Open WhatsApp Business", SupportedLaunchApp.WHATSAPP_BUSINESS))
        assertFalse(AppLaunchPolicy.hasExplicitIntent("Open WhatsApp and Instagram", SupportedLaunchApp.WHATSAPP))
        assertFalse(AppLaunchPolicy.hasExplicitIntent("Open WhatsApp and YouTube Music", SupportedLaunchApp.WHATSAPP))
        assertTrue(AppLaunchPolicy.hasExplicitIntent("Open Google Meet", SupportedLaunchApp.GOOGLE_MEET))
        assertFalse(AppLaunchPolicy.hasExplicitIntent("Open Google Meet", SupportedLaunchApp.MESSENGER))
        assertTrue(AppLaunchPolicy.hasExplicitIntent("Launch ChatGPT", SupportedLaunchApp.CHATGPT))
        assertTrue(AppLaunchPolicy.hasExplicitIntent("Start Twitter", SupportedLaunchApp.X_APP))
        assertTrue(AppLaunchPolicy.hasExplicitIntent("Open the phone dialer", SupportedLaunchApp.PHONE))
        assertTrue(AppLaunchPolicy.hasExplicitIntent("Open Google Contacts", SupportedLaunchApp.CONTACTS))
        assertFalse(AppLaunchPolicy.hasExplicitIntent("Show me my contacts", SupportedLaunchApp.CONTACTS))
        assertFalse(AppLaunchPolicy.hasExplicitIntent("Open contacts and phone", SupportedLaunchApp.CONTACTS))
    }

    @Test fun declarationExposesOnlyCuratedAppKeysAndReviewBehavior() {
        val declarations = GeminiSafeTools.declaration().getJSONArray("functionDeclarations")
        val app = (0 until declarations.length()).map { declarations.getJSONObject(it) }
            .single { it.getString("name") == GeminiSafeTools.OPEN_APP }
        assertTrue(app.getString("description").contains("only after approval"))
        assertTrue(app.getString("description").contains("arbitrary package names"))
        val values = app.getJSONObject("parameters").getJSONObject("properties")
            .getJSONObject("app").getJSONArray("enum")
        assertEquals(SupportedLaunchApp.values().map { it.key }.toSet(),
            (0 until values.length()).map { values.getString(it) }.toSet())
    }
}
