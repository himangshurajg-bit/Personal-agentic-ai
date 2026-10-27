package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SourceQuickCommandsTest {
    @Test fun matchesOriginalTermuxQuickCommandLabelsAndPromptsInOrder() {
        assertEquals(
            listOf(
                "Battery" to "battery kitni hai?",
                "Torch on" to "torch on karo",
                "Location" to "meri location batao",
                "WhatsApp" to "whatsapp kholo",
                "YouTube" to "youtube kholo",
                "Alarm" to "subah 6 baje ka alarm lagao",
                "Wi-Fi" to "wifi ka haal batao",
                "Camera" to "camera kholo",
            ),
            SourceQuickCommands.all.map { it.label to it.prompt },
        )
    }

    @Test fun labelsAndPromptsAreNonblankAndUnique() {
        val commands = SourceQuickCommands.all
        assertTrue(commands.isNotEmpty())
        assertTrue(commands.all { it.label.isNotBlank() && it.prompt.isNotBlank() })
        assertEquals(commands.size, commands.map { it.label }.distinct().size)
    }
}
