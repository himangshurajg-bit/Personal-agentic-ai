import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'assistant_state.dart';

/// Reads a bounded, read-only Android snapshot only after the owner taps Refresh.
class DeviceStatusScreen extends StatefulWidget {
  const DeviceStatusScreen({super.key});

  @override
  State<DeviceStatusScreen> createState() => _DeviceStatusScreenState();
}

class _DeviceStatusScreenState extends State<DeviceStatusScreen> {
  Map<String, Object?>? _snapshot;
  bool _loading = false;
  String? _error;

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await AssistantState.device
          .invokeMapMethod<String, Object?>('read_device_status_snapshot');
      if (!mounted) return;
      setState(() {
        _snapshot = result;
        if (result == null) _error = 'Android returned no device status.';
      });
    } on PlatformException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.message ?? 'Device status is unavailable.',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Device status is unavailable.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _snapshot;
    final rows = data == null ? const <_StatusRow>[] : _rows(data);
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Text(
              'Read-only snapshot from this phone. Nothing is monitored or saved; refresh only when you want a current reading. No location or network identifiers are collected.',
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _loading ? null : _refresh,
          icon: _loading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded),
          label: Text(_loading ? 'Reading status…' : 'Refresh device status'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (data == null && _error == null) ...[
          const SizedBox(height: 20),
          const Center(
            child: Text('Tap refresh to read the current device status.'),
          ),
        ],
        for (final row in rows) ...[
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              title: Text(row.title),
              subtitle: row.detail == null ? null : Text(row.detail!),
              trailing: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Text(row.value, textAlign: TextAlign.end),
              ),
            ),
          ),
        ],
      ],
    );
  }

  List<_StatusRow> _rows(Map<String, Object?> data) {
    String text(String key) {
      final value = data[key];
      return value == null || value.toString().isEmpty
          ? 'Unavailable'
          : value.toString();
    }

    String bytes(String key) {
      final value = data[key];
      if (value is! num || value < 0) return 'Unavailable';
      var scaled = value.toDouble();
      const units = ['B', 'KB', 'MB', 'GB', 'TB'];
      var unit = 0;
      while (scaled >= 1024 && unit < units.length - 1) {
        scaled /= 1024;
        unit++;
      }
      return unit == 0
          ? '${scaled.round()} ${units[unit]}'
          : '${scaled.toStringAsFixed(1)} ${units[unit]}';
    }

    String uptime() {
      final value = data['uptime_ms'];
      if (value is! num || value < 0) return 'Unavailable';
      final duration = Duration(milliseconds: value.toInt());
      final hours = duration.inHours;
      final minutes = duration.inMinutes.remainder(60);
      final seconds = duration.inSeconds.remainder(60);
      return hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m ${seconds}s';
    }

    String display() {
      final width = data['display_width_px'];
      final height = data['display_height_px'];
      if (width is! num || height is! num) return 'Unavailable';
      return '${width.toInt()} × ${height.toInt()} px';
    }

    String brightness() {
      final value = data['brightness_level'];
      final percent = data['brightness_percent'];
      if (value is! num || percent is! num) return 'Unavailable';
      return '${percent.toInt()}% (${value.toInt()}/255)';
    }

    String batteryTemperature() {
      final value = data['battery_temperature_c'];
      return value is num ? '${value.toStringAsFixed(1)} °C' : 'Unavailable';
    }

    String refreshRate() {
      final value = data['display_refresh_hz'];
      return value is num ? '${value.toStringAsFixed(1)} Hz' : 'Unavailable';
    }

    String batteryPercent() {
      final value = data['battery_percent'];
      return value is num ? '${value.toInt()}%' : 'Unavailable';
    }

    String notificationState() {
      final value = data['notifications_enabled'];
      return value is bool ? (value ? 'Allowed' : 'Blocked') : 'Unavailable';
    }

    final density = data['display_density_dpi'];
    return [
      _StatusRow('Local time', text('local_time'), text('time_zone')),
      _StatusRow(
        'Android',
        '${text('android_release')} (API ${text('android_sdk')})',
        'Security patch: ${text('security_patch')}',
      ),
      _StatusRow(
        'Personal AI',
        text('app_version'),
        'Build ${text('app_build')}',
      ),
      _StatusRow('Uptime', uptime(), 'Since this phone last booted'),
      _StatusRow(
        'Storage',
        '${bytes('storage_available_bytes')} free',
        '${bytes('storage_total_bytes')} total internal storage',
      ),
      _StatusRow(
        'Memory',
        '${bytes('memory_available_bytes')} available',
        '${bytes('memory_total_bytes')} total system RAM',
      ),
      _StatusRow(
        'Display',
        display(),
        'Density ${density is num ? density.toInt() : 'Unavailable'} dpi · ${refreshRate()}',
      ),
      _StatusRow('Locale', text('locale')),
      _StatusRow('Ringer', text('ringer_mode')),
      _StatusRow('System theme', text('system_theme')),
      _StatusRow('Thermal status', text('thermal_status')),
      _StatusRow(
        'Battery saver',
        text('battery_saver') == 'true'
            ? 'On'
            : text('battery_saver') == 'false'
            ? 'Off'
            : 'Unavailable',
      ),
      _StatusRow('Brightness', brightness()),
      _StatusRow('App notifications', notificationState()),
      _StatusRow(
        'Battery',
        batteryPercent(),
        '${text('battery_status')} · ${text('battery_health')}',
      ),
      _StatusRow(
        'Battery temperature',
        batteryTemperature(),
        'Voltage ${text('battery_voltage_mv')} mV · ${text('battery_chemistry')}',
      ),
    ];
  }
}

class _StatusRow {
  const _StatusRow(this.title, this.value, [this.detail]);
  final String title;
  final String value;
  final String? detail;
}
