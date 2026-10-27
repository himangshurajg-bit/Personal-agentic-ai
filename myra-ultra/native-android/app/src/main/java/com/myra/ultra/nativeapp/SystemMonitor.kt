package com.myra.ultra.nativeapp

/** Aggregate counters from Linux /proc/stat's first `cpu` row. */
data class CpuTicks(val total: Long, val idle: Long)

data class CpuUsageSample(val sampledAt: Long, val percent: Int)

data class NetworkCounterSample(val sampledAt: Long, val receivedBytes: Long, val transmittedBytes: Long)
data class NetworkRateSample(val sampledAt: Long, val receivedBytesPerSecond: Long, val transmittedBytesPerSecond: Long)

/** Keeps only recent in-screen samples; no persistence or background collection. */
object CpuUsageHistory {
    const val MAX_SAMPLES = 60

    fun append(history: List<CpuUsageSample>, sample: CpuUsageSample): List<CpuUsageSample> =
        (history + sample.copy(percent = sample.percent.coerceIn(0, 100))).takeLast(MAX_SAMPLES)
}

object NetworkUsageHistory {
    const val MAX_SAMPLES = 60

    /** Computes device-wide byte rates from monotonic elapsed-time samples; resets/unavailable counters are skipped. */
    fun rate(previous: NetworkCounterSample?, current: NetworkCounterSample?): NetworkRateSample? {
        if (previous == null || current == null) return null
        val elapsed = current.sampledAt - previous.sampledAt
        if (elapsed <= 0 || previous.receivedBytes < 0 || previous.transmittedBytes < 0 ||
            current.receivedBytes < previous.receivedBytes || current.transmittedBytes < previous.transmittedBytes) return null
        fun perSecond(delta: Long): Long = ((delta.toDouble() * 1000.0) / elapsed).coerceAtMost(Long.MAX_VALUE.toDouble()).toLong()
        return NetworkRateSample(
            current.sampledAt,
            perSecond(current.receivedBytes - previous.receivedBytes),
            perSecond(current.transmittedBytes - previous.transmittedBytes),
        )
    }

    fun append(history: List<NetworkRateSample>, sample: NetworkRateSample): List<NetworkRateSample> =
        (history + sample.copy(receivedBytesPerSecond = sample.receivedBytesPerSecond.coerceAtLeast(0), transmittedBytesPerSecond = sample.transmittedBytesPerSecond.coerceAtLeast(0)))
            .takeLast(MAX_SAMPLES)
}

object SystemMonitorData {
    /** Parses the aggregate CPU row; guest counters are excluded because Linux already includes them in user/nice. */
    fun parseCpuTicks(line: String): CpuTicks? {
        val fields = line.trim().split(Regex("\\s+"))
        if (fields.firstOrNull() != "cpu" || fields.size < 5) return null
        val values = fields.drop(1).take(8).map { it.toLongOrNull() ?: return null }
        if (values.any { it < 0 }) return null
        val total = values.fold(0L) { acc, value ->
            if (Long.MAX_VALUE - acc < value) return null
            acc + value
        }
        val idle = values[3] + (values.getOrNull(4) ?: 0L)
        if (idle < values[3] || idle > total) return null
        return CpuTicks(total, idle)
    }

    /** Returns null for the first sample, a reset counter, or an unusable interval. */
    fun cpuUsagePercent(previous: CpuTicks?, current: CpuTicks?): Int? {
        if (previous == null || current == null) return null
        val totalDelta = current.total - previous.total
        val idleDelta = current.idle - previous.idle
        if (totalDelta <= 0 || idleDelta < 0 || idleDelta > totalDelta) return null
        return (((totalDelta - idleDelta).toDouble() / totalDelta) * 100.0)
            .toInt().coerceIn(0, 100)
    }

    fun formatBytes(bytes: Long): String {
        if (bytes < 0) return "Unavailable"
        if (bytes < 1024) return "$bytes B"
        val units = arrayOf("KB", "MB", "GB", "TB", "PB")
        var value = bytes.toDouble()
        var unit = -1
        while (value >= 1024.0 && unit < units.lastIndex) {
            value /= 1024.0
            unit++
        }
        return String.format(java.util.Locale.ROOT, "%.1f %s", value, units[unit])
    }
}
