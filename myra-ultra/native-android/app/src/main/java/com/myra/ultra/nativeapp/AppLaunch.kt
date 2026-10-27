package com.myra.ultra.nativeapp

import java.io.IOException
import java.util.Locale
import org.json.JSONObject

internal data class GeminiAppLaunchRequest(val app: SupportedLaunchApp) {
    val displayName: String get() = app.displayName
}

/** Curated prototype-backed app handoff; arbitrary package names and package enumeration are not allowed. */
internal enum class SupportedLaunchApp(
    val key: String,
    val displayName: String,
    val packageName: String,
    val aliases: List<String>,
) {
    CALCULATOR("calculator", "Calculator", "com.google.android.calculator", listOf("calculator")),
    CAMERA("camera", "Camera", "com.android.camera", listOf("camera")),
    CHROME("chrome", "Chrome", "com.android.chrome", listOf("chrome", "google chrome")),
    CLOCK("clock", "Clock", "com.google.android.deskclock", listOf("clock")),
    FILES("files", "Files", "com.google.android.apps.nbu.files", listOf("files", "file manager")),
    GMAIL("gmail", "Gmail", "com.google.android.gm", listOf("gmail", "google mail")),
    MAPS("maps", "Maps", "com.google.android.apps.maps", listOf("maps", "google maps")),
    SETTINGS("settings", "Settings", "com.android.settings", listOf("settings", "android settings")),
    SPOTIFY("spotify", "Spotify", "com.spotify.music", listOf("spotify")),
    YOUTUBE("youtube", "YouTube", "com.google.android.youtube", listOf("youtube")),
    WHATSAPP("whatsapp", "WhatsApp", "com.whatsapp", listOf("whatsapp")),
    WHATSAPP_BUSINESS("whatsapp_business", "WhatsApp Business", "com.whatsapp.w4b", listOf("whatsapp business")),
    INSTAGRAM("instagram", "Instagram", "com.instagram.android", listOf("instagram")),
    YOUTUBE_MUSIC("youtube_music", "YouTube Music", "com.google.android.apps.youtube.music", listOf("youtube music")),
    PHOTOS("photos", "Google Photos", "com.google.android.apps.photos", listOf("google photos", "photos")),
    MESSAGES("messages", "Messages", "com.google.android.apps.messaging", listOf("messages", "google messages")),
    TELEGRAM("telegram", "Telegram", "org.telegram.messenger", listOf("telegram")),
    CALENDAR("calendar", "Google Calendar", "com.google.android.calendar", listOf("google calendar", "calendar")),
    DRIVE("drive", "Google Drive", "com.google.android.apps.docs", listOf("google drive", "drive")),
    PLAY_STORE("play_store", "Play Store", "com.android.vending", listOf("play store", "google play store")),
    PHONE("phone", "Phone", "com.google.android.dialer", listOf("phone", "dialer", "phone dialer")),
    CONTACTS("contacts", "Contacts", "com.google.android.contacts", listOf("contacts", "google contacts")),
    FACEBOOK("facebook", "Facebook", "com.facebook.katana", listOf("facebook")),
    LINKEDIN("linkedin", "LinkedIn", "com.linkedin.android", listOf("linkedin")),
    AMAZON("amazon", "Amazon", "in.amazon.mShop.android.shopping", listOf("amazon")),
    CHATGPT("chatgpt", "ChatGPT", "com.openai.chatgpt", listOf("chatgpt", "chat gpt")),
    FLIPKART("flipkart", "Flipkart", "com.flipkart.android", listOf("flipkart")),
    GEMINI("gemini", "Gemini", "com.google.android.apps.bard", listOf("gemini")),
    GOOGLE_MEET("google_meet", "Google Meet", "com.google.android.apps.tachyon", listOf("google meet", "meet")),
    MESSENGER("messenger", "Messenger", "com.facebook.orca", listOf("messenger", "facebook messenger")),
    NETFLIX("netflix", "Netflix", "com.netflix.mediaclient", listOf("netflix")),
    OLA("ola", "Ola", "com.olacabs.customer", listOf("ola")),
    SNAPCHAT("snapchat", "Snapchat", "com.snapchat.android", listOf("snapchat")),
    SWIGGY("swiggy", "Swiggy", "in.swiggy.android", listOf("swiggy")),
    UBER("uber", "Uber", "com.ubercab", listOf("uber")),
    X_APP("x_app", "X", "com.twitter.android", listOf("x", "x app", "twitter")),
    ZOMATO("zomato", "Zomato", "com.application.zomato", listOf("zomato")),
    ZOOM("zoom", "Zoom", "us.zoom.videomeet", listOf("zoom"));

    companion object {
        fun fromKey(value: String): SupportedLaunchApp? = values().firstOrNull { it.key == value }
    }
}

internal object AppLaunchPolicy {
    fun request(args: JSONObject): GeminiAppLaunchRequest {
        if (args.length() != 1 || !args.has("app")) throw IOException("Gemini requested unexpected app-launch arguments; no app was opened.")
        val key = args.opt("app") as? String
            ?: throw IOException("Gemini requested an invalid app name; no app was opened.")
        val app = SupportedLaunchApp.fromKey(key)
            ?: throw IOException("That app is not in MYRA's limited launch list; no app was opened.")
        return GeminiAppLaunchRequest(app)
    }

    /** Require an explicit, latest-turn app-opening request naming exactly the same single supported app. */
    fun hasExplicitIntent(userText: String, app: SupportedLaunchApp): Boolean {
        val text = userText.lowercase(Locale.ROOT)
        if (Regex("\\b(don't|do not|never|not)\\s+(open|launch|start)\\b").containsMatchIn(text)) return false
        if (!Regex("\\b(open|launch|start)\\b").containsMatchIn(text)) return false
        data class AliasMatch(val app: SupportedLaunchApp, val start: Int, val end: Int)
        val matches = SupportedLaunchApp.values().flatMap { candidate ->
            candidate.aliases.flatMap { alias ->
                Regex("(?<![a-z0-9])${Regex.escape(alias)}(?![a-z0-9])").findAll(text)
                    .map { AliasMatch(candidate, it.range.first, it.range.last + 1) }.toList()
            }
        }
        if (matches.isEmpty()) return false
        // Ignore a shorter alias fully contained in a longer product name, but retain
        // separate app mentions even when their names have different lengths.
        val unshadowed = matches.filterNot { short ->
            matches.any { long -> long.end - long.start > short.end - short.start &&
                long.start <= short.start && long.end >= short.end }
        }
        val mentioned = unshadowed.map { it.app }.distinct()
        if (mentioned.size != 1 || mentioned.single() != app) return false
        val targetPattern = app.aliases.joinToString("|") { Regex.escape(it) }
        return Regex("\\b(open|launch|start)\\b.{0,60}(?<![a-z0-9])(?:$targetPattern)(?![a-z0-9])", RegexOption.IGNORE_CASE)
            .containsMatchIn(userText)
    }
}
