import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'assistant_state.dart';

/// A user-started, read-only Wi-Fi status check and Android settings handoff.
class WifiSettingsScreen extends StatefulWidget {
  const WifiSettingsScreen({super.key});

  @override
  State<WifiSettingsScreen> createState() => _WifiSettingsScreenState();
}

class _WifiSettingsScreenState extends State<WifiSettingsScreen> {
  bool? _enabled;
  bool _checking = false;
  bool _opening = false;
  String? _error;
  String? _notice;

  Future<void> _checkStatus() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _error = null;
      _notice = null;
    });
    try {
      final response = await AssistantState.device
          .invokeMapMethod<String, Object?>('read_wifi_status');
      final enabled = response?['enabled'];
      if (enabled is! bool) {
        throw const PlatformException(
          code: 'invalid_response',
          message: 'Android did not return a Wi-Fi enabled state.',
        );
      }
      if (mounted) setState(() => _enabled = enabled);
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() => _error = error.message ?? 'Wi-Fi status is unavailable.');
      }
    } on MissingPluginException {
      if (mounted) setState(() => _error = 'Wi-Fi status is available in the Android app only.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Wi-Fi status is unavailable.');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _openSettings() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _error = null;
      _notice = null;
    });
    try {
      final response = await AssistantState.device
          .invokeMapMethod<String, Object?>('open_wifi_settings');
      if (response?['opened'] != true) {
        throw const PlatformException(
          code: 'not_opened',
          message: 'Android did not confirm opening its Wi-Fi settings.',
        );
      }
      if (mounted) {
        setState(() => _notice = 'Android opened connectivity settings. Review and change Wi-Fi there if you choose.');
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() => _error = error.message ?? 'Android could not open Wi-Fi settings.');
      }
    } on MissingPluginException {
      if (mounted) setState(() => _error = 'Wi-Fi settings are available in the Android app only.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Android could not open Wi-Fi settings.');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Wi-Fi status', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'Check only whether Wi-Fi is enabled, or open Android connectivity settings. Personal AI does not read network names or signal details and never toggles Wi-Fi itself.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _enabled == null
                      ? 'Status not checked'
                      : _enabled! ? 'Wi-Fi is enabled' : 'Wi-Fi is disabled',
                  key: const Key('wifi-status-value'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const Key('wifi-check'),
                  onPressed: _checking ? null : _checkStatus,
                  icon: _checking
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh_rounded),
                  label: const Text('Check Wi-Fi status'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('wifi-open-settings'),
          onPressed: _opening ? null : _openSettings,
          icon: _opening
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.settings_rounded),
          label: const Text('Open connectivity settings'),
        ),
        if (_notice != null) ...[
          const SizedBox(height: 12),
          Text(_notice!, style: TextStyle(color: colors.primary)),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: colors.error)),
        ],
      ],
    );
  }
}
