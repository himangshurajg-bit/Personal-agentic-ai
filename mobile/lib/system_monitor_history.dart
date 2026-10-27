/// A point captured by an explicit System Monitor history action.
///
/// These values are kept only in the screen's in-memory session; they are never
/// persisted or sampled in the background.
class SystemMonitorSample {
  const SystemMonitorSample({
    required this.capturedAt,
    required this.cpuPercent,
    required this.memoryUsedPercent,
  });

  final DateTime capturedAt;
  final int? cpuPercent;
  final double? memoryUsedPercent;

  factory SystemMonitorSample.fromMetrics(
    Map<String, Object?> metrics, {
    DateTime? capturedAt,
  }) {
    final rawCpu = metrics['cpu_percent'];
    final cpuPercent =
        rawCpu is num && rawCpu.isFinite && rawCpu >= 0 && rawCpu <= 100
        ? rawCpu.round()
        : null;

    final rawAvailable = metrics['memory_available_bytes'];
    final rawTotal = metrics['memory_total_bytes'];
    double? memoryUsedPercent;
    if (rawAvailable is num &&
        rawTotal is num &&
        rawAvailable.isFinite &&
        rawTotal.isFinite &&
        rawAvailable >= 0 &&
        rawTotal > 0 &&
        rawAvailable <= rawTotal) {
      memoryUsedPercent = (100 * (rawTotal - rawAvailable) / rawTotal)
          .clamp(0, 100)
          .toDouble();
    }

    return SystemMonitorSample(
      capturedAt: capturedAt ?? DateTime.now(),
      cpuPercent: cpuPercent,
      memoryUsedPercent: memoryUsedPercent,
    );
  }
}

/// Bounded, in-memory history for one open monitor session.
class SystemMonitorHistory {
  SystemMonitorHistory({this.maximumSamples = 60}) : assert(maximumSamples > 0);

  final int maximumSamples;
  final List<SystemMonitorSample> _samples = [];

  List<SystemMonitorSample> get samples => List.unmodifiable(_samples);

  void add(SystemMonitorSample sample) {
    _samples.add(sample);
    if (_samples.length > maximumSamples) {
      _samples.removeRange(0, _samples.length - maximumSamples);
    }
  }

  void clear() => _samples.clear();
}
