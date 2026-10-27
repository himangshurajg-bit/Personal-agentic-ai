package com.myra.ultra.nativeapp

/** The original Termux chat's visible quick prompts, kept verbatim for the Android chat UI. */
data class SourceQuickCommand(val label: String, val prompt: String)

object SourceQuickCommands {
    val all = listOf(
        SourceQuickCommand("Battery", "battery kitni hai?"),
        SourceQuickCommand("Torch on", "torch on karo"),
        SourceQuickCommand("Location", "meri location batao"),
        SourceQuickCommand("WhatsApp", "whatsapp kholo"),
        SourceQuickCommand("YouTube", "youtube kholo"),
        SourceQuickCommand("Alarm", "subah 6 baje ka alarm lagao"),
        SourceQuickCommand("Wi-Fi", "wifi ka haal batao"),
        SourceQuickCommand("Camera", "camera kholo"),
    )
}
