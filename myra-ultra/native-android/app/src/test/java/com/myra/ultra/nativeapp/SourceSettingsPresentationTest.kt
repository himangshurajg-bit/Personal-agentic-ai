package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SourceSettingsPresentationTest {
    @Test fun systemBarsFollowThePrototypeAndroidWrapper() {
        assertEquals(0xFF101116L, SourceChromePresentation.systemBarColorArgb)
        assertEquals(false, SourceChromePresentation.windowLightStatusBar)
    }

    @Test fun sourceBackdropUsesPrototypeBlackAlpha() {
        assertEquals(170f / 255f, SourceSettingsPresentation.backdropDimAmount, 0.0001f)
    }

    @Test fun sourceResponsiveSheetAndLanguageListBoundsAreApplied() {
        assertEquals(560, SourceSettingsPresentation.maxWidthDp)
        assertEquals(0.88f, SourceSettingsPresentation.sheetHeightFraction)
        assertEquals(0.30f, SourceSettingsPresentation.languageListHeightFraction)
        assertEquals(48, SourceSettingsPresentation.fieldMinHeightDp)
        assertEquals(704, SourceSettingsPresentation.maxSheetHeightDp(800f))
        assertEquals(240, SourceSettingsPresentation.maxLanguageListHeightDp(800f))
        assertEquals(0, SourceSettingsPresentation.maxSheetHeightDp(-10f))
    }

    @Test fun listPrependsAutoAndCapsAtFirstEightyInSourceOrder() {
        val all = SourceSettingsPresentation.filterLanguages("")
        assertEquals("auto", all.first().code)
        assertEquals("Auto — Hinglish", all.first().englishName)
        assertEquals(80, all.size)
        assertEquals(LanguagePreference.options.take(79).map { it.code }, all.drop(1).map { it.code })
    }

    @Test fun searchMatchesCodeEnglishAndNativeNamesAndReturnsNoFalseMatch() {
        assertTrue(SourceSettingsPresentation.filterLanguages(" hi ").any { it.code == "hi" })
        assertTrue(SourceSettingsPresentation.filterLanguages("தமிழ்").any { it.code == "ta" })
        assertTrue(SourceSettingsPresentation.filterLanguages("en-IN").any { it.code == "en-IN" })
        assertEquals(emptyList<LanguageOption>(), SourceSettingsPresentation.filterLanguages("not-a-language"))
    }

    @Test fun draftDefaultsFollowSourceAutoAndBargeInOffAndEditsStayStaged() {
        val initial = SourceSettingsDraft.from("", null, null, false)
        assertEquals("auto", initial.languageCode)
        assertFalse(initial.bargeInEnabled)
        assertEquals(GeminiModelCatalog.resolveId(null), initial.modelId)
        val edited = initial.copy(name = "Riya", bargeInEnabled = true).withLanguage("ta")
        assertEquals("", initial.name) // discard/cancel leaves the saved draft source untouched
        assertFalse(initial.bargeInEnabled)
        assertEquals("Riya", edited.name)
        assertTrue(edited.bargeInEnabled)
        assertEquals("ta", edited.languageCode)
        assertEquals(30, SourceSettingsDraft.from("x".repeat(40), null, null, true).name.length)
    }
}
