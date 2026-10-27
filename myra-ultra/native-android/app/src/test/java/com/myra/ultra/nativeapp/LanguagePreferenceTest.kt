package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LanguagePreferenceTest {
    @Test fun catalogHasUniqueCodesAndCoversThePrototypeLanguages() {
        assertTrue(LanguagePreference.options.size >= 140)
        assertEquals(LanguagePreference.options.size, LanguagePreference.options.map { it.code.lowercase() }.toSet().size)
        assertEquals("as", LanguagePreference.resolveCode("Assamese"))
        assertEquals("hi", LanguagePreference.resolveCode("हिन्दी"))
        assertEquals("en-IN", LanguagePreference.resolveCode("English (India)"))
    }

    @Test fun resolvesSavedCodesAndMigratesLegacyDisplayNames() {
        assertEquals("ta", LanguagePreference.resolveCode("ta"))
        assertEquals("as", LanguagePreference.resolveCode("Assamese"))
        assertEquals(LanguagePreference.DEFAULT_CODE, LanguagePreference.resolveCode(null))
        assertEquals(LanguagePreference.DEFAULT_CODE, LanguagePreference.resolveCode("not-a-supported-language"))
    }

    @Test fun automaticLanguageMatchesPrototypeDefaultWithoutForcingAnOutputLanguage() {
        assertEquals("auto", LanguagePreference.resolveCode(null))
        assertEquals("Auto — Hinglish", LanguagePreference.option(null).englishName)
        assertEquals("", LanguagePreference.promptInstruction(null))
        assertEquals("", LanguagePreference.promptInstruction("auto"))
    }

    @Test fun promptInstructionNamesSelectedLanguageAndPreservesTechnicalIdentifiers() {
        val prompt = LanguagePreference.promptInstruction("as")
        assertTrue(prompt.contains("Assamese"))
        assertTrue(prompt.contains("অসমীয়া"))
        assertTrue(prompt.contains("URLs"))
    }

    @Test fun hinglishUsesLatinScriptGuidance() {
        val prompt = LanguagePreference.promptInstruction("hi-Latn")
        assertTrue(prompt.contains("Hinglish"))
        assertTrue(prompt.contains("Latin script"))
    }

    @Test fun legacyEnglishSettingIsRecognized() {
        assertEquals("en-US", LanguagePreference.resolveCode("English"))
    }
}
