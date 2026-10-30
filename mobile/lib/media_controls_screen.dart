import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'assistant_state.dart';

/// User-reviewed media search handoffs and on-demand Android volume control.
class MediaControlsScreen extends StatefulWidget {
  const MediaControlsScreen({super.key});

  @override
  State<MediaControlsScreen> createState() => _MediaControlsScreenState();
}

class _MediaControlsScreenState extends State<MediaControlsScreen> {
  static const _services = <String, String>{
    'youtube': 'YouTube',
    'spotify': 'Spotify',
  };
  static const _streams = <String, String>{
    'music': 'Music',
    'ring': 'Ring',
    'alarm': 'Alarm',
    'notification': 'Notification',
    'system': 'System',
    'call': 'Voice call',
  };

  final _query = TextEditingController();
  String _service = 'youtube';
  String _stream = 'music';
  int _percent = 50;
  Map<String, Object?>? _volume;
  bool _searching = false;
  bool _reading = false;
  bool _applying = false;
  String? _message;
  String? _error;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  bool get _validQuery {
    final value = _query.text.trim();
    return value.isNotEmpty &&
        value.length <= 120 &&
        !value.runes.any((rune) => rune < 32 || (rune >= 127 && rune <= 159));
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    if (!_validQuery || _searching) {
      setState(() => _error = 'Enter a search up to 120 characters.');
      return;
    }
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Review ${_services[_service]} search'),
        content: Text(
          'Search for “$query”? This opens search results only; playback will not start.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Open search'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() {
      _searching = true;
      _error = null;
      _message = null;
    });
    try {
      final response = await AssistantState.device
          .invokeMapMethod<String, Object?>('open_media_search', {
            'service': _service,
            'query': query,
          });
      if (response?['opened'] == true &&
          response?['playback_started'] == false) {
        if (mounted) {
          setState(
            () => _message =
                'Android opened the search handoff. Playback was not started.',
          );
        }
      } else {
        throw PlatformException(
          code: 'unconfirmed',
          message: 'Android did not confirm opening the search handoff.',
        );
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.message ?? 'Android could not open the search.',
        );
      }
    } on MissingPluginException {
      if (mounted) {
        setState(
          () => _error = 'Media search is available in the Android app only.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Android could not confirm opening the search.',
        );
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _readVolume() async {
    if (_reading) return;
    setState(() {
      _reading = true;
      _error = null;
      _message = null;
    });
    try {
      final response = await AssistantState.device
          .invokeMapMethod<String, Object?>('read_volume_state', {
            'stream': _stream,
          });
      final percent = response?['percent'];
      final current = response?['current'];
      final min = response?['min'];
      final max = response?['max'];
      if (response == null ||
          percent is! num ||
          current is! num ||
          min is! num ||
          max is! num ||
          percent < 0 ||
          percent > 100 ||
          min > current ||
          current > max) {
        throw PlatformException(
          code: 'invalid_response',
          message: 'Android returned an invalid volume range.',
        );
      }
      if (mounted) {
        setState(() {
          _volume = response;
          _percent = percent.round();
        });
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.message ?? 'Android volume is unavailable.',
        );
      }
    } on MissingPluginException {
      if (mounted) {
        setState(
          () =>
              _error = 'Volume controls are available in the Android app only.',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Android volume is unavailable.');
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _applyVolume() async {
    if (_volume == null || _applying) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Review volume change'),
        content: Text('Set ${_streams[_stream]} volume to $_percent%?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apply volume'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() {
      _applying = true;
      _error = null;
      _message = null;
    });
    try {
      final response = await AssistantState.device
          .invokeMapMethod<String, Object?>('set_reviewed_volume', {
            'stream': _stream,
            'percent': _percent,
          });
      final actual = response?['actual_percent'];
      final applied = response?['applied'];
      if (actual is! num || applied is! bool) {
        throw PlatformException(
          code: 'invalid_response',
          message: 'Android did not confirm the resulting volume.',
        );
      }
      if (mounted) {
        setState(() {
          _volume = response;
          _percent = actual.round();
          _message =
              applied == true &&
                  actual.round() == response?['requested_percent']
              ? 'Android reports ${(_streams[_stream] ?? 'volume').toLowerCase()} volume set to ${actual.round()}%.'
              : 'Android reports ${(_streams[_stream] ?? 'volume').toLowerCase()} volume at ${actual.round()}%; the requested level was not reached.';
        });
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(
          () => _error =
              error.message ?? 'Android could not confirm the volume change.',
        );
      }
    } on MissingPluginException {
      if (mounted) {
        setState(
          () =>
              _error = 'Volume controls are available in the Android app only.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Android could not confirm the volume change.');
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final rangeIsAdjustable =
        _volume != null && _volume!['min'] != _volume!['max'];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        Text('Media search', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(
          'Search YouTube or Spotify after reviewing the exact query. This only opens search results; it never starts playback.',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  key: const Key('media-service'),
                  initialValue: _service,
                  decoration: const InputDecoration(
                    labelText: 'Search service',
                  ),
                  items: _services.entries
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _service = value ?? 'youtube'),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('media-query'),
                  controller: _query,
                  maxLength: 120,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Search query',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => FocusScope.of(context).unfocus(),
                  onChanged: (_) => setState(() {
                    _error = null;
                    _message = null;
                  }),
                ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('media-review-search'),
                    onPressed: _validQuery && !_searching ? _search : null,
                    icon: _searching
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search_rounded),
                    label: const Text('Review media search'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('Android volume', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(
          'Volume is read only when you tap below. Choose a stream and level; the exact change must be reviewed before Android applies it.',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  key: const Key('volume-stream'),
                  initialValue: _stream,
                  decoration: const InputDecoration(labelText: 'Audio stream'),
                  items: _streams.entries
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() {
                    _stream = value ?? 'music';
                    _volume = null;
                    _message = null;
                    _error = null;
                  }),
                ),
                const SizedBox(height: 12),
                Text(
                  _volume == null
                      ? 'Volume not read'
                      : 'Current: ${_volume!['current']} of ${_volume!['max']} · $_percent%',
                  key: const Key('volume-current'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  key: const Key('volume-read'),
                  onPressed: _reading ? null : _readVolume,
                  icon: _reading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                  label: const Text('Read current volume'),
                ),
                if (_volume != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('0%'),
                      Expanded(
                        child: Slider(
                          key: const Key('volume-slider'),
                          value: _percent.toDouble(),
                          min: 0,
                          max: 100,
                          divisions: 100,
                          label: '$_percent%',
                          onChanged: rangeIsAdjustable
                              ? (value) => setState(() {
                                  _percent = value.round();
                                  _message = null;
                                })
                              : null,
                        ),
                      ),
                      const Text('100%'),
                    ],
                  ),
                  Text(
                    'Requested level: $_percent%',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      key: const Key('volume-review-apply'),
                      onPressed: rangeIsAdjustable && !_applying
                          ? _applyVolume
                          : null,
                      icon: _applying
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.volume_up_rounded),
                      label: const Text('Review volume change'),
                    ),
                  ),
                  if (!rangeIsAdjustable)
                    const Text(
                      'Android reports this stream cannot be adjusted.',
                    ),
                ],
              ],
            ),
          ),
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(
            _message!,
            key: const Key('media-volume-message'),
            style: TextStyle(color: colors.primary),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            key: const Key('media-volume-error'),
            style: TextStyle(color: colors.error),
          ),
        ],
      ],
    );
  }
}
