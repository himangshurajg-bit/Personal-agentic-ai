package com.myra.ultra.nativeapp

/** Only non-identifying Wi-Fi state is shared with Gemini; network names and addresses are never read. */
data class WifiStatusSnapshot(
    val enabled: Boolean,
    /** Null means Android could not report the active network state. */
    val connected: Boolean?,
    /** RSSI in dBm when connected and reported; may be null when unavailable. */
    val rssiDbm: Int?,
)

object WifiStatusFormatter {
    fun format(snapshot: WifiStatusSnapshot): String {
        val connection = when {
            !snapshot.enabled -> "Wi-Fi is disabled."
            snapshot.connected == true -> "Wi-Fi is enabled and Android reports an active Wi-Fi connection."
            snapshot.connected == false -> "Wi-Fi is enabled, but Android reports no active Wi-Fi connection."
            else -> "Wi-Fi is enabled; Android could not report connection state."
        }
        val signal = if (snapshot.enabled && snapshot.connected == true && snapshot.rssiDbm != null && snapshot.rssiDbm > -127 && snapshot.rssiDbm <= 0) {
            " Signal strength: ${snapshot.rssiDbm} dBm."
        } else ""
        return "$connection$signal No SSID, BSSID, or IP address was read."
    }
}
