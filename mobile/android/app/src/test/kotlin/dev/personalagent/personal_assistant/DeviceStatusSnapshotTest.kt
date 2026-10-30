package dev.personalagent.personal_assistant

import android.os.PowerManager
import android.media.AudioManager
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DeviceStatusSnapshotTest {
    @Test fun batteryPercentRejectsInvalidScaleOrLevel() {
        assertEquals(50, DeviceStatusSnapshot.batteryPercent(50, 100))
        assertEquals(33, DeviceStatusSnapshot.batteryPercent(1, 3))
        assertNull(DeviceStatusSnapshot.batteryPercent(-1, 100))
        assertNull(DeviceStatusSnapshot.batteryPercent(101, 100))
        assertNull(DeviceStatusSnapshot.batteryPercent(1, 0))
    }

    @Test fun ringerAndThermalValuesAreNamedAndUnknownValuesStayUnavailable() {
        assertEquals("normal", DeviceStatusSnapshot.ringerModeLabel(AudioManager.RINGER_MODE_NORMAL))
        assertEquals("vibrate", DeviceStatusSnapshot.ringerModeLabel(AudioManager.RINGER_MODE_VIBRATE))
        assertEquals("silent", DeviceStatusSnapshot.ringerModeLabel(AudioManager.RINGER_MODE_SILENT))
        assertNull(DeviceStatusSnapshot.ringerModeLabel(99))
        assertEquals("none", DeviceStatusSnapshot.thermalStatusLabel(PowerManager.THERMAL_STATUS_NONE))
        assertEquals("moderate", DeviceStatusSnapshot.thermalStatusLabel(PowerManager.THERMAL_STATUS_MODERATE))
        assertEquals("critical", DeviceStatusSnapshot.thermalStatusLabel(PowerManager.THERMAL_STATUS_CRITICAL))
        assertNull(DeviceStatusSnapshot.thermalStatusLabel(99))
    }
}
