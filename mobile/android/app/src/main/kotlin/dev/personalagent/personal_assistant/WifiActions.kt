package dev.personalagent.personal_assistant

/** Minimal Wi-Fi status and settings intent mapping; this never changes radio state. */
internal object WifiActions {
    const val INTERNET_CONNECTIVITY_PANEL = "android.settings.panel.action.INTERNET_CONNECTIVITY"
    const val WIFI_SETTINGS = "android.settings.WIFI_SETTINGS"

    fun statusLabel(enabled: Boolean): String = if (enabled) "Wi-Fi is enabled." else "Wi-Fi is disabled."
}
