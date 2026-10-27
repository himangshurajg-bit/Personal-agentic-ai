package com.myra.ultra.nativeapp

import android.os.BatteryManager
import org.junit.Assert.assertEquals
import org.junit.Test

class BatteryStatusFormatterTest {
    @Test fun includesAvailableAndroidBatteryDetailsWithCorrectUnits() {
        assertEquals(
            "72% · charging or full · health: good · temperature: 31.2 °C · voltage: 3.90 V · chemistry: Li-ion",
            BatteryStatusFormatter.format(
                72,
                BatteryManager.BATTERY_STATUS_CHARGING,
                BatteryManager.BATTERY_HEALTH_GOOD,
                312,
                3900,
                " Li-ion ",
            ),
        )
    }

    @Test fun omitsOptionalFieldsWhenAndroidDoesNotSupplyThem() {
        assertEquals(
            "50% · not charging",
            BatteryStatusFormatter.format(50, BatteryManager.BATTERY_STATUS_DISCHARGING, null, null, null, null),
        )
    }

    @Test fun rejectsInvalidMeasurementsAndSanitizesTechnologyText() {
        val result = BatteryStatusFormatter.format(100, null, 999, 20_000, -1, "Li-ion\nInjected")
        assertEquals("100% · charging state unavailable · chemistry: Li-ionInjected", result)
    }

    @Test fun invalidPercentageReturnsClearUnavailableResult() {
        assertEquals(
            "Battery percentage unavailable; Android did not return a valid reading.",
            BatteryStatusFormatter.format(-1, null, null, null, null, null),
        )
    }
}
