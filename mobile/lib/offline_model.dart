import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const int gemma4ModelSizeBytes = 2588147712;
const int qwen3ModelSizeBytes = 613722264;
const int gemma4StorageReserveBytes = 536870912;

bool offlineModelDownloadHasSpace({
  required int availableBytes,
  required int partialBytes,
  required int modelSizeBytes,
}) {
  var savedBytes = partialBytes;
  if (savedBytes < 0 || savedBytes > modelSizeBytes) savedBytes = 0;
  final remainingBytes = modelSizeBytes - savedBytes;
  return availableBytes >= remainingBytes + gemma4StorageReserveBytes;
}

bool gemma4DownloadHasSpace({
  required int availableBytes,
  required int partialBytes,
}) => offlineModelDownloadHasSpace(
  availableBytes: availableBytes,
  partialBytes: partialBytes,
  modelSizeBytes: gemma4ModelSizeBytes,
);

/// Opt-in model manager for fixed screening and separately enabled experimental local chat.
class OfflineModelPanel extends StatefulWidget {
  const OfflineModelPanel({super.key});

  @override
  State<OfflineModelPanel> createState() => _OfflineModelPanelState();
}

class _OfflineModelPanelState extends State<OfflineModelPanel>
    with WidgetsBindingObserver {
  static const _methods = MethodChannel('personal_assistant/offline_model');
  static const _events = EventChannel('personal_assistant/offline_model/events');
  static const _fixtures = <(String, String)>[
    ('english', 'English · Newton’s law'),
    ('assamese', 'Assamese · Newton’s law'),
    ('arithmetic', 'Arithmetic · units'),
    ('jee', 'Class 12/JEE · tutoring'),
    ('hindi', 'Hindi · Devanagari'),
    ('hinglish', 'Hinglish · Roman script'),
  ];

  StreamSubscription<Object?>? _subscription;
  Map<String, dynamic> _status = <String, dynamic>{};
  String _selectedFixture = 'english';
  String _stage = 'checking';
  String _message = 'Checking local model storage…';
  String _output = '';
  Map<String, dynamic> _metrics = <String, dynamic>{};
  bool _calling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscription = _events.receiveBroadcastStream().listen(
      _onEvent,
      onError: (Object error) {
        if (mounted) setState(() => _message = 'Native screening events are unavailable.');
      },
    );
    _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    super.dispose();
  }

  void _onEvent(Object? raw) {
    if (!mounted || raw is! Map) return;
    final event = Map<String, dynamic>.from(raw);
    final kind = event.remove('kind') as String? ?? '';
    setState(() {
      if (kind == 'status') _status.addAll(event);
      if (kind == 'download_state') {
        _status['download_active'] = event['state'] == 'starting' || event['state'] == 'downloading' || event['state'] == 'verifying';
        if (event['bytes'] is num) _status['partial_bytes'] = event['bytes'];
      }
      if (kind == 'download_state' || kind == 'runtime_state' || kind == 'inference_state') {
        _stage = event['state'] as String? ?? _stage;
        _message = event['message'] as String? ?? _message;
        if (kind == 'inference_state') {
          _status['inference_active'] = _stage == 'running';
          if (event['text'] is String) _output = event['text'] as String;
        }
        if (kind == 'runtime_state') _status['runtime_loaded'] = _stage == 'loaded';
      } else if (kind == 'download_progress') {
        _stage = 'downloading';
        _status['partial_bytes'] = event['bytes'];
      } else if (kind == 'inference_delta') {
        _output += event['text'] as String? ?? '';
      } else if (kind == 'inference_result') {
        _stage = 'complete';
        _message = event['message'] as String? ?? 'Screening output only.';
        _output = event['text'] as String? ?? _output;
        _metrics = event;
      }
    });
    if (kind == 'status' || kind == 'download_state') _refresh();
  }

  Future<void> _refresh() async {
    try {
      final value = await _methods.invokeMapMethod<String, dynamic>('status');
      if (mounted && value != null) setState(() => _status = value);
    } on PlatformException {
      if (mounted) setState(() => _message = 'This Android build does not expose the local model screen yet.');
    }
  }

  Future<bool> _confirm(String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(action)),
          ],
        ),
      ) ??
      false;

  Future<void> _invoke(String method, [Map<String, Object?>? arguments]) async {
    if (_calling) return;
    setState(() => _calling = true);
    try {
      await _methods.invokeMethod<Object?>(method, arguments);
      await _refresh();
    } on PlatformException catch (error) {
      if (mounted) setState(() => _message = error.message ?? 'The local operation could not start.');
    } finally {
      if (mounted) setState(() => _calling = false);
    }
  }

  String _formatModelSize(int bytes) => bytes >= 1000000000
      ? '${(bytes / 1000000000).toStringAsFixed(2)} GB'
      : '${(bytes / 1000000).toStringAsFixed(0)} MB';

  String _formatBytes(Object? value) {
    if (value is! num || value < 0) return 'unavailable';
    final bytes = value.toInt();
    if (bytes < 1024 * 1024) return '$bytes B';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final modelPresent = _status['model_present'] == true;
    final previousModelPresent = _status['previous_model_present'] == true;
    final previousPartialPresent = _status['previous_partial_present'] == true;
    final sizeMatches = _status['model_size_matches'] == true;
    final loaded = _status['runtime_loaded'] == true;
    final downloading = _status['download_active'] == true || _stage == 'downloading';
    final bytes = (_status['partial_bytes'] as num?)?.toInt() ?? 0;
    final selectedModelId = _status['selected_model_id'] as String? ?? 'gemma-4-E2B-it';
    final isQwen = selectedModelId == 'qwen3-0.6b';
    final selectedModelName = isQwen ? 'Qwen3 0.6B' : 'Gemma 4 E2B';
    final selectedModelDescription = _status['model_description'] as String? ?? '5.1B total · 2.3B effective parameters · 8 GB minimum listed';
    final total = (_status['model_bytes'] as num?)?.toInt() ?? gemma4ModelSizeBytes;
    final progress = (bytes / total).clamp(0.0, 1.0).toDouble();
    final free = (_status['available_bytes'] as num?)?.toInt() ?? 0;
    final canDownload = offlineModelDownloadHasSpace(
      availableBytes: free,
      partialBytes: bytes,
      modelSizeBytes: total,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.memory_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$selectedModelName · experimental local AI', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 5),
                      Text('$selectedModelDescription · ${_status['license'] ?? 'Apache-2.0'}', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                const Chip(avatar: Icon(Icons.lock_outline, size: 16), label: Text('Not qualified')),
              ],
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: selectedModelId,
              decoration: const InputDecoration(labelText: 'Offline model'),
              items: const [
                DropdownMenuItem(value: 'gemma-4-E2B-it', child: Text('Gemma 4 E2B · larger option')),
                DropdownMenuItem(value: 'qwen3-0.6b', child: Text('Qwen3 0.6B · lighter option')),
              ],
              onChanged: _calling || _status['model_selection_locked'] == true
                  ? null
                  : (value) { if (value != null) _invoke('select_model', {'model_id': value}); },
            ),
            if (_status['other_model_present'] == true) ...[
              const SizedBox(height: 6),
              Text('The other model file stays in app storage when you switch. Select it to remove its files.', style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 14),
            Text('${_formatModelSize(total)} model · ${isQwen ? 'device-memory minimum not published' : '8 GB minimum listed'} · app-private storage · no network inference', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(
              'Available RAM: ${_formatBytes(_status['available_memory_bytes'])}${_status['low_memory'] == true ? ' · Android reports low memory' : ''}. This is only a momentary reading, not a fit guarantee.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Text('${isQwen ? 'Qwen3 is a much smaller LiteRT-LM option, but its fit and quality on lower-end phones are untested; no device-memory minimum is published.' : 'The allowlist minimum is 8 GB RAM, which is not a fit guarantee; runtime headroom and Redmi performance are untested.'} Downloading or loading can use substantial storage, memory, battery and heat. Normal chat needs a separate experimental opt-in; this model is not qualified for your phone.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            if (previousModelPresent || previousPartialPresent) ...[
              const SizedBox(height: 8),
              const Text('A previous Gemma 4 E4B model or partial download is still in app storage. The selected option will not use it; remove files below only if you want to reclaim that space.'),
            ],
            const SizedBox(height: 14),
            if (downloading) ...[
              LinearProgressIndicator(value: progress == 0 ? null : progress),
              const SizedBox(height: 8),
              Text('Downloaded ${_formatBytes(bytes)} of ${_formatModelSize(total)} · resumes only when you start it again', style: theme.textTheme.labelMedium),
            ],
            if (_message.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_message, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!modelPresent && !downloading)
                  FilledButton.icon(
                    onPressed: _calling || !canDownload
                        ? null
                        : () async {
                            final proceed = await _confirm(
                              bytes > 0 ? 'Resume model download?' : 'Download model for offline chat?',
                              'This starts a user-requested ${_formatModelSize(total)} download of $selectedModelName. It uses app-private storage and keeps 512 MB free as a reserve. Downloading alone does not load it or opt it into normal chat.',
                              bytes > 0 ? 'Resume download' : 'Download',
                            );
                            if (proceed && mounted) await _invoke('download');
                          },
                    icon: const Icon(Icons.download_outlined),
                    label: Text(bytes > 0 ? 'Resume download' : 'Download for offline chat'),
                  ),
                if (downloading)
                  OutlinedButton.icon(onPressed: _calling ? null : () => _invoke('cancel_download'), icon: const Icon(Icons.pause_rounded), label: const Text('Pause')),
                if (modelPresent && !loaded)
                  FilledButton.icon(
                    onPressed: _calling || !sizeMatches ? null : () async {
                      final proceed = await _confirm('Load $selectedModelName locally?', 'This checks Android’s low-memory warning first, then loads the model in app memory. It may still fail, run slowly, or heat the phone. It remains unqualified. If you explicitly opted in above, the loaded model can also answer normal chat without network fallback.', 'Load model');
                      if (proceed && mounted) await _invoke('load_for_screening');
                    },
                    icon: const Icon(Icons.memory_rounded),
                    label: const Text('Load for screening / chat'),
                  ),
                if (loaded)
                  OutlinedButton.icon(onPressed: _calling ? null : () => _invoke('unload_candidate'), icon: const Icon(Icons.memory_outlined), label: const Text('Unload from memory')),
                if (loaded && !(_status['inference_active'] == true))
                  TextButton.icon(onPressed: _calling ? null : () async {
                    setState(() { _output = ''; _metrics = <String, dynamic>{}; });
                    await _invoke('run_qualification', {'fixture_id': _selectedFixture});
                  }, icon: const Icon(Icons.play_arrow_rounded), label: const Text('Run fixed prompt')),
                if (_status['inference_active'] == true)
                  OutlinedButton.icon(onPressed: _calling ? null : () => _invoke('cancel_inference'), icon: const Icon(Icons.stop_rounded), label: const Text('Cancel test')),
                if ((modelPresent || bytes > 0 || previousModelPresent || previousPartialPresent) && !downloading && !loaded)
                  TextButton.icon(onPressed: _calling ? null : () async {
                    final proceed = await _confirm('Remove model files?', 'This removes the selected $selectedModelName model and partial download, plus any previous Gemma 4 E4B files. The other model option is kept; it does not affect chat history or online settings.', 'Remove model');
                    if (proceed && mounted) await _invoke('remove_model');
                  }, icon: const Icon(Icons.delete_outline), label: const Text('Remove files')),
                if (!modelPresent && !downloading && !canDownload)
                  Text('Not enough free app storage: ${_formatBytes(free)} available.', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.error)),
              ],
            ),
            if (loaded) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _selectedFixture,
                decoration: const InputDecoration(labelText: 'Fixed screening prompt'),
                items: [for (final fixture in _fixtures) DropdownMenuItem(value: fixture.$1, child: Text(fixture.$2))],
                onChanged: (_status['inference_active'] == true) ? null : (value) { if (value != null) setState(() => _selectedFixture = value); },
              ),
              const SizedBox(height: 8),
              Text('Run each prompt several times and review the answer yourself. This panel reports samples and device measurements; it never marks the model as passed.', style: theme.textTheme.bodySmall),
            ],
            if (_output.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('Local sample · $_selectedFixture', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              Container(width: double.infinity, padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)), child: SelectableText(_output)),
            ],
            if (_metrics.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Elapsed ${_metrics['elapsed_ms']} ms · process PSS ${_metrics['pss_before_mb']} → ${_metrics['pss_after_mb']} MB · thermal status ${_metrics['thermal_before']} → ${_metrics['thermal_after']}', style: theme.textTheme.labelSmall),
            ],
            const SizedBox(height: 10),
            Text('Experimental chat uses the loaded model only after the separate Settings opt-in. Fixed samples are not stored or sent. Nothing here qualifies answer quality or Redmi/HyperOS behavior.', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
