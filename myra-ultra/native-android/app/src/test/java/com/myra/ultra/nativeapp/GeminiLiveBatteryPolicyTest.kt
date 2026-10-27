package com.myra.ultra.nativeapp

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GeminiLiveBatteryPolicyTest {
    @Test fun allowsDirectEnglishAndHinglishBatteryStatusQuestions() {
        listOf(
            "What's my phone battery percentage?",
            "Check my battery status",
            "How much battery is left?",
            "Is my battery low?",
            "Battery kitni hai?",
            "Meri battery ka haal batao",
        ).forEach { assertTrue("Expected direct battery question: $it", GeminiLiveBatteryPolicy.hasExplicitIntent(it)) }
    }

    @Test fun rejectsIncidentalNegativeHypotheticalOrUnrelatedRequests() {
        listOf(
            "My battery is low",
            "Don't check my battery",
            "If I ask about battery later, tell me",
            "What is the weather?",
            "Check my phone storage",
            "Battery tomorrow",
            "Can you explain how batteries work?",
        ).forEach { assertFalse("Must not read battery for: $it", GeminiLiveBatteryPolicy.hasExplicitIntent(it)) }
    }
}
