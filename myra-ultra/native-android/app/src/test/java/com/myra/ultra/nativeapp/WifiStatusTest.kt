package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Test

class WifiStatusTest {
    @Test fun disabledStateDoesNotClaimConnectionOrSignal() {
        assertEquals(
            "Wi-Fi is disabled. No SSID, BSSID, or IP address was read.",
            WifiStatusFormatter.format(WifiStatusSnapshot(enabled = false, connected = null, rssiDbm = null)),
        )
    }

    @Test fun connectedStateIncludesOnlyAvailableRssiAndNoNetworkIdentifiers() {
        assertEquals(
            "Wi-Fi is enabled and Android reports an active Wi-Fi connection. Signal strength: -58 dBm. No SSID, BSSID, or IP address was read.",
            WifiStatusFormatter.format(WifiStatusSnapshot(enabled = true, connected = true, rssiDbm = -58)),
        )
        assertEquals(
            "Wi-Fi is enabled and Android reports an active Wi-Fi connection. No SSID, BSSID, or IP address was read.",
            WifiStatusFormatter.format(WifiStatusSnapshot(enabled = true, connected = true, rssiDbm = -127)),
        )
    }

    @Test fun unavailableConnectionStateAndDisconnectedStateStayDistinct() {
        assertEquals(
            "Wi-Fi is enabled, but Android reports no active Wi-Fi connection. No SSID, BSSID, or IP address was read.",
            WifiStatusFormatter.format(WifiStatusSnapshot(enabled = true, connected = false, rssiDbm = null)),
        )
        assertEquals(
            "Wi-Fi is enabled; Android could not report connection state. No SSID, BSSID, or IP address was read.",
            WifiStatusFormatter.format(WifiStatusSnapshot(enabled = true, connected = null, rssiDbm = null)),
        )
    }

    @Test fun invalidRssiIsOmitted() {
        val result = WifiStatusFormatter.format(WifiStatusSnapshot(enabled = true, connected = true, rssiDbm = 12))
        assertEquals(false, result.contains("Signal strength"))
    }
}
