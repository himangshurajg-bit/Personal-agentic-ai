import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/system_monitor_history.dart';

void main() {
  test('derives bounded CPU and memory percentages from a snapshot', () {
    final sample = SystemMonitorSample.fromMetrics({
      'cpu_percent': 42.4,
      'memory_available_bytes': 25,
      'memory_total_bytes': 100,
    }, capturedAt: DateTime.utc(2026, 10, 27));

    expect(sample.cpuPercent, 42);
    expect(sample.memoryUsedPercent, 75);
    expect(sample.capturedAt, DateTime.utc(2026, 10, 27));
  });

  test('invalid metrics stay unavailable instead of fabricating a trend', () {
    final sample = SystemMonitorSample.fromMetrics({
      'cpu_percent': 101,
      'memory_available_bytes': 101,
      'memory_total_bytes': 100,
    });

    expect(sample.cpuPercent, isNull);
    expect(sample.memoryUsedPercent, isNull);
  });

  test('history retains only the newest configured number of samples', () {
    final history = SystemMonitorHistory(maximumSamples: 2);
    final start = DateTime.utc(2026, 10, 27);
    for (var index = 0; index < 3; index++) {
      history.add(
        SystemMonitorSample(
          capturedAt: start.add(Duration(seconds: index)),
          cpuPercent: index,
          memoryUsedPercent: index.toDouble(),
        ),
      );
    }

    expect(history.samples.map((sample) => sample.cpuPercent), [1, 2]);
    history.clear();
    expect(history.samples, isEmpty);
  });
}
