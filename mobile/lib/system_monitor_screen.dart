import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'assistant_state.dart';

/// Read-only, on-demand snapshot of aggregate device counters.
class SystemMonitorScreen extends StatefulWidget {
  const SystemMonitorScreen({super.key});

  @override
  State<SystemMonitorScreen> createState() => _SystemMonitorScreenState();
}

class _SystemMonitorScreenState extends State<SystemMonitorScreen> {
  Map<String, Object?>? _metrics;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
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
        setState(() => _metrics = result);
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

  @override
  Widget build(BuildContext context) {
    final metrics = _metrics;
    final cpu = metrics?['cpu_percent'];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Read-only snapshot. Metrics are fetched only when this screen opens or you refresh; nothing is tracked in the background or saved.',
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _loading ? null : _refresh,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            label: Text(_loading ? 'Reading…' : 'Refresh'),
          ),
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
      ],
    );
  }
}
