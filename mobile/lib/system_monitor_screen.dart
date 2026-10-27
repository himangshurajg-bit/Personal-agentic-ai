import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'assistant_state.dart';
import 'system_monitor_history.dart';

/// Read-only, on-demand snapshot and optional in-memory session history.
class SystemMonitorScreen extends StatefulWidget {
  const SystemMonitorScreen({super.key});

  @override
  State<SystemMonitorScreen> createState() => _SystemMonitorScreenState();
}

class _SystemMonitorScreenState extends State<SystemMonitorScreen> {
  Map<String, Object?>? _metrics;
  bool _loading = false;
  String? _error;
  final SystemMonitorHistory _history = SystemMonitorHistory();

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh({bool captureHistory = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await AssistantState.device
          .invokeMapMethod<String, Object?>('read_system_metrics');
      if (!mounted) return;
      if (result == null) {
        setState(() => _error = 'Android returned no system metrics.');
      } else {
        setState(() {
          _metrics = result;
          if (captureHistory) {
            _history.add(SystemMonitorSample.fromMetrics(result));
          }
        });
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() => _error = error.message ?? 'Metrics unavailable.');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Metrics unavailable.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _bytes(Object? value) {
    if (value is! num || value < 0) return 'Unavailable';
    final bytes = value.toDouble();
    if (bytes < 1024) return '${bytes.round()} B';
    const units = ['KB', 'MB', 'GB', 'TB', 'PB'];
    var scaled = bytes;
    var unit = -1;
    while (scaled >= 1024 && unit < units.length - 1) {
      scaled /= 1024;
      unit++;
    }
    return '${scaled.toStringAsFixed(1)} ${units[unit]}';
  }

  Widget _metric(String title, String value, String detail, IconData icon) =>
      Card(
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(detail),
          trailing: Text(value, textAlign: TextAlign.end),
        ),
      );

  Widget _historyCard(BuildContext context) {
    final samples = _history.samples;
    final colors = Theme.of(context).colorScheme;
    final countLabel = samples.length == 1
        ? '1 captured sample'
        : '${samples.length} captured samples';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Session history',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (samples.isNotEmpty)
                  TextButton.icon(
                    key: const ValueKey('clear-monitor-history'),
                    onPressed: () => setState(_history.clear),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Clear'),
                  ),
              ],
            ),
            Text('$countLabel · in memory only, up to 60 samples'),
            const SizedBox(height: 8),
            if (samples.length < 2)
              const Text('Capture another sample to see a trend.')
            else ...[
              Wrap(
                spacing: 16,
                children: [
                  _legend(colors.primary, 'CPU busy'),
                  _legend(colors.tertiary, 'Memory used'),
                ],
              ),
              const SizedBox(height: 8),
              Semantics(
                label: 'Session trend chart. CPU busy and memory used, from earlier to latest sample.',
                child: SizedBox(
                  height: 144,
                  width: double.infinity,
                  child: CustomPaint(
                    key: const ValueKey('system-monitor-history-chart'),
                    painter: _HistoryPainter(
                      samples: samples,
                      cpuColor: colors.primary,
                      memoryColor: colors.tertiary,
                      gridColor: colors.outlineVariant,
                    ),
                  ),
                ),
              ),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [Text('Earlier'), Text('Latest')],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _legend(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(label),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final metrics = _metrics;
    final cpu = metrics?['cpu_percent'];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Read-only metrics. A snapshot is fetched only when this screen opens or you refresh. History is captured only when you tap the button below; it stays in memory and is never saved or sampled in the background.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _loading ? null : () => _refresh(),
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: Text(_loading ? 'Reading…' : 'Refresh snapshot'),
            ),
            FilledButton.tonalIcon(
              key: const ValueKey('capture-monitor-history'),
              onPressed: _loading ? null : () => _refresh(captureHistory: true),
              icon: const Icon(Icons.add_chart),
              label: const Text('Capture history sample'),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (metrics != null) ...[
          const SizedBox(height: 8),
          _metric(
            'CPU busy',
            cpu is num ? '${cpu.round()}%' : 'Sample again',
            cpu is num
                ? 'Change since the previous refresh'
                : 'The first sample sets a baseline; refresh once more.',
            Icons.memory,
          ),
          _metric(
            'Memory',
            '${_bytes(metrics['memory_available_bytes'])} free',
            '${_bytes(metrics['memory_total_bytes'])} total system memory',
            Icons.storage,
          ),
          _metric(
            'App data storage',
            '${_bytes(metrics['storage_free_bytes'])} free',
            '${_bytes(metrics['storage_total_bytes'])} total on the app data volume',
            Icons.sd_storage_outlined,
          ),
          _metric(
            'Network received',
            _bytes(metrics['network_received_bytes']),
            'Device-wide total since boot; not attributed to this app.',
            Icons.south_rounded,
          ),
          _metric(
            'Network sent',
            _bytes(metrics['network_sent_bytes']),
            'Device-wide total since boot; not attributed to this app.',
            Icons.north_rounded,
          ),
        ],
        const SizedBox(height: 8),
        _historyCard(context),
      ],
    );
  }
}

class _HistoryPainter extends CustomPainter {
  const _HistoryPainter({
    required this.samples,
    required this.cpuColor,
    required this.memoryColor,
    required this.gridColor,
  });

  final List<SystemMonitorSample> samples;
  final Color cpuColor;
  final Color memoryColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 10.0;
    final plot = Rect.fromLTRB(
      inset,
      inset,
      size.width - inset,
      size.height - inset,
    );
    if (plot.width <= 0 || plot.height <= 0) return;

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final fraction in [0.0, 0.5, 1.0]) {
      final y = plot.bottom - plot.height * fraction;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
    }
    _drawSeries(canvas, plot, cpuColor, (sample) => sample.cpuPercent);
    _drawSeries(
      canvas,
      plot,
      memoryColor,
      (sample) => sample.memoryUsedPercent,
    );
  }

  void _drawSeries(
    Canvas canvas,
    Rect plot,
    Color color,
    num? Function(SystemMonitorSample sample) valueFor,
  ) {
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final dot = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    Offset? previous;
    for (var index = 0; index < samples.length; index++) {
      final value = valueFor(samples[index]);
      if (value == null || !value.isFinite) {
        previous = null;
        continue;
      }
      final x = plot.left + plot.width * index / (samples.length - 1);
      final y = plot.bottom - plot.height * value.clamp(0, 100) / 100;
      final point = Offset(x, y.toDouble());
      if (previous != null) canvas.drawLine(previous, point, stroke);
      canvas.drawCircle(point, 2.5, dot);
      previous = point;
    }
  }

  @override
  bool shouldRepaint(covariant _HistoryPainter oldDelegate) =>
      oldDelegate.samples != samples ||
      oldDelegate.cpuColor != cpuColor ||
      oldDelegate.memoryColor != memoryColor ||
      oldDelegate.gridColor != gridColor;
}
