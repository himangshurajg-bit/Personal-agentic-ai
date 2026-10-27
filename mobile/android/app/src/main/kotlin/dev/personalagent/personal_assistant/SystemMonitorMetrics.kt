package dev.personalagent.personal_assistant

/** Read-only helpers for aggregate Linux CPU counters and display formatting. */
internal data class SystemCpuTicks(val total: Long, val idle: Long)

internal object SystemMonitorMetrics {
    fun parseCpuTicks(line: String): SystemCpuTicks? {
        val fields = line.trim().split(Regex("\\s+"))
        if (fields.firstOrNull() != "cpu" || fields.size < 5) return null
        val values = fields.drop(1).take(8).map { it.toLongOrNull() ?: return null }
        if (values.any { it < 0 }) return null
        var total = 0L
        for (value in values) {
            if (Long.MAX_VALUE - total < value) return null
            total += value
        }
        val idle = values[3] + (values.getOrNull(4) ?: 0L)
        if (idle < values[3] || idle > total) return null
        return SystemCpuTicks(total, idle)
    }

    fun cpuPercent(previous: SystemCpuTicks?, current: SystemCpuTicks?): Int? {
        if (previous == null || current == null) return null
        val totalDelta = current.total - previous.total
        val idleDelta = current.idle - previous.idle
        if (totalDelta <= 0 || idleDelta < 0 || idleDelta > totalDelta) return null
        return (((totalDelta - idleDelta).toDouble() / totalDelta) * 100.0)
            .toInt().coerceIn(0, 100)
    }

    fun formatBytes(bytes: Long?): String {
        if (bytes == null || bytes < 0) return "Unavailable"
        if (bytes < 1024) return "$bytes B"
        val units = arrayOf("KB", "MB", "GB", "TB", "PB")
        var value = bytes.toDouble()
        var index = -1
        while (value >= 1024.0 && index < units.lastIndex) {
            value /= 1024.0
            index++
        }
        return String.format(java.util.Locale.ROOT, "%.1f %s", value, units[index])
    }
}
