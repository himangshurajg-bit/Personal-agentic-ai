package com.myra.ultra.nativeapp

/** Exact settings-list and sizing rules derived from the prototype's dialog and CSS. */
internal object SourceSettingsPresentation {
    const val maxWidthDp = 560
    const val sheetHeightFraction = 0.88f
    const val languageListHeightFraction = 0.30f
    const val languageResultLimit = 80
    const val fieldMinHeightDp = 48
    // Source dialog::backdrop is #000a (170/255 opacity).
    const val backdropDimAmount = 170f / 255f

    fun maxSheetHeightDp(availableHeightDp: Float): Int =
        (availableHeightDp.coerceAtLeast(0f) * sheetHeightFraction).toInt()

    fun maxLanguageListHeightDp(availableHeightDp: Float): Int =
        (availableHeightDp.coerceAtLeast(0f) * languageListHeightFraction).toInt()

    fun filterLanguages(query: String): List<LanguageOption> {
        val normalized = query.trim().lowercase(java.util.Locale.ROOT)
        return (listOf(LanguagePreference.autoOption) + LanguagePreference.options)
            .filter { option ->
                normalized.isEmpty() || listOf(option.code, option.englishName, option.nativeName)
                    .any { it.lowercase(java.util.Locale.ROOT).contains(normalized) }
            }
            .take(languageResultLimit)
    }
}

/** Values staged while the settings sheet is open; Cancel simply discards this value. */
internal data class SourceSettingsDraft(
    val name: String,
    val languageCode: String,
    val modelId: String,
    val bargeInEnabled: Boolean,
) {
    fun withLanguage(code: String) = copy(languageCode = LanguagePreference.resolveCode(code))

    companion object {
        fun from(name: String, languageCode: String?, modelId: String?, bargeInEnabled: Boolean) =
            SourceSettingsDraft(
                name = name.take(30),
                languageCode = LanguagePreference.resolveCode(languageCode),
                modelId = GeminiModelCatalog.resolveId(modelId),
                bargeInEnabled = bargeInEnabled,
            )
    }
}
