package dev.personalagent.personal_assistant

import org.junit.Assert.assertEquals
import org.junit.Test

class WifiActionsTest {
    @Test fun statusReportsOnlyEnabledOrDisabled() {
        assertEquals("Wi-Fi is enabled.", WifiActions.statusLabel(true))
        assertEquals("Wi-Fi is disabled.", WifiActions.statusLabel(false))
    }

    @Test fun settingsActionsUseConnectivityPanelThenWifiSettingsFallback() {
        assertEquals("android.settings.panel.action.INTERNET_CONNECTIVITY", WifiActions.INTERNET_CONNECTIVITY_PANEL)
        assertEquals("android.settings.WIFI_SETTINGS", WifiActions.WIFI_SETTINGS)
    }
}
