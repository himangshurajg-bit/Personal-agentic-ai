package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SystemMonitorDataTest {
    @Test fun parsesAggregateCpuCountersAndIncludesIoWaitAsIdle() {
        assertEquals(CpuTicks(total = 100, idle = 65), SystemMonitorData.parseCpuTicks("cpu 10 2 20 60 5 1 1 1 9 2"))
        assertNull(SystemMonitorData.parseCpuTicks("cpu0 1 2 3 4"))
        assertNull(SystemMonitorData.parseCpuTicks("cpu 1 2 nope 4"))
        assertNull(SystemMonitorData.parseCpuTicks("cpu 1 2 3"))
    }

    @Test fun computesBusyPercentFromCounterDeltas() {
        val previous = CpuTicks(total = 100, idle = 80)
        assertEquals(50, SystemMonitorData.cpuUsagePercent(previous, CpuTicks(total = 200, idle = 130)))
        assertEquals(0, SystemMonitorData.cpuUsagePercent(previous, CpuTicks(total = 200, idle = 180)))
        assertEquals(100, SystemMonitorData.cpuUsagePercent(previous, CpuTicks(total = 200, idle = 80)))
        assertNull(SystemMonitorData.cpuUsagePercent(null, CpuTicks(200, 100)))
        assertNull(SystemMonitorData.cpuUsagePercent(previous, CpuTicks(90, 70)))
    }

    @Test fun cpuHistoryKeepsRecentBoundedSamplesAndClampsValues() {
        val history = (0 until 65).fold(emptyList<CpuUsageSample>()) { acc, index ->
            CpuUsageHistory.append(acc, CpuUsageSample(index.toLong(), if (index == 64) 120 else index))
        }
        assertEquals(CpuUsageHistory.MAX_SAMPLES, history.size)
        assertEquals(5L, history.first().sampledAt)
        assertEquals(64L, history.last().sampledAt)
        assertEquals(100, history.last().percent)
    }

    @Test fun cpuHistoryDoesNotMutateEarlierSnapshot() {
        val initial = listOf(CpuUsageSample(1, 25))
        val next = CpuUsageHistory.append(initial, CpuUsageSample(2, 50))
        assertEquals(listOf(CpuUsageSample(1, 25)), initial)
        assertEquals(listOf(CpuUsageSample(1, 25), CpuUsageSample(2, 50)), next)
    }

    @Test fun networkRateUsesMonotonicCounterDeltas() {
        assertEquals(
            NetworkRateSample(4_000, 1_000, 500),
            NetworkUsageHistory.rate(NetworkCounterSample(2_000, 2_000, 1_000), NetworkCounterSample(4_000, 4_000, 2_000)),
        )
        assertEquals(NetworkRateSample(5_000, 0, 0), NetworkUsageHistory.rate(NetworkCounterSample(4_000, 4_000, 2_000), NetworkCounterSample(5_000, 4_000, 2_000)))
    }

    @Test fun networkRateRejectsUnavailableResetAndNonmonotonicSamples() {
        assertNull(NetworkUsageHistory.rate(null, NetworkCounterSample(2_000, 100, 100)))
        assertNull(NetworkUsageHistory.rate(NetworkCounterSample(1_000, -1, 100), NetworkCounterSample(2_000, 100, 200)))
        assertNull(NetworkUsageHistory.rate(NetworkCounterSample(2_000, 100, 100), NetworkCounterSample(1_000, 200, 200)))
        assertNull(NetworkUsageHistory.rate(NetworkCounterSample(1_000, 100, 100), NetworkCounterSample(2_000, 50, 200)))
    }

    @Test fun networkHistoryRetainsOnlyRecentSamplesAndDoesNotMutatePriorList() {
        val initial = listOf(NetworkRateSample(1, 5, 3))
        val next = NetworkUsageHistory.append(initial, NetworkRateSample(2, 7, 4))
        assertEquals(listOf(NetworkRateSample(1, 5, 3)), initial)
        assertEquals(listOf(NetworkRateSample(1, 5, 3), NetworkRateSample(2, 7, 4)), next)
        val capped = (0 until 65).fold(emptyList<NetworkRateSample>()) { acc, index ->
            NetworkUsageHistory.append(acc, NetworkRateSample(index.toLong(), index.toLong(), index.toLong()))
        }
        assertEquals(NetworkUsageHistory.MAX_SAMPLES, capped.size)
        assertEquals(5L, capped.first().sampledAt)
    }

    @Test fun formatsByteCountsWithoutLocaleDependentUnits() {
        assertEquals("0 B", SystemMonitorData.formatBytes(0))
        assertEquals("1023 B", SystemMonitorData.formatBytes(1023))
        assertEquals("1.0 KB", SystemMonitorData.formatBytes(1024))
        assertEquals("1.5 MB", SystemMonitorData.formatBytes(1572864))
        assertEquals("Unavailable", SystemMonitorData.formatBytes(-1))
    }
}
