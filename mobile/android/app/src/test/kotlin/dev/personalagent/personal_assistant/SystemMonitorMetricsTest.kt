package dev.personalagent.personal_assistant

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SystemMonitorMetricsTest {
    @Test fun parsesAggregateCpuAndRejectsMalformedRows() {
        assertEquals(SystemCpuTicks(100, 65), SystemMonitorMetrics.parseCpuTicks("cpu 10 2 20 60 5 1 1 1 9"))
        assertNull(SystemMonitorMetrics.parseCpuTicks("cpu0 1 2 3 4"))
        assertNull(SystemMonitorMetrics.parseCpuTicks("cpu 1 2 nope 4"))
    }

    @Test fun calculatesCpuDeltaAndHandlesFirstOrResetSample() {
        assertEquals(35, SystemMonitorMetrics.cpuPercent(SystemCpuTicks(100, 65), SystemCpuTicks(200, 130)))
        assertNull(SystemMonitorMetrics.cpuPercent(null, SystemCpuTicks(200, 130)))
        assertNull(SystemMonitorMetrics.cpuPercent(SystemCpuTicks(200, 130), SystemCpuTicks(100, 65)))
    }

    @Test fun formatsByteCountsAndUnavailableValues() {
        assertEquals("0 B", SystemMonitorMetrics.formatBytes(0))
        assertEquals("1.0 KB", SystemMonitorMetrics.formatBytes(1024))
        assertEquals("Unavailable", SystemMonitorMetrics.formatBytes(null))
        assertEquals("Unavailable", SystemMonitorMetrics.formatBytes(-1))
    }
}
