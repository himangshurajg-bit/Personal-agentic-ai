import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'clipboard_text_preview.dart';

class ClipboardPreviewScreen extends StatefulWidget {
  const ClipboardPreviewScreen({super.key});

  @override
  State<ClipboardPreviewScreen> createState() => _ClipboardPreviewScreenState();
}

class _ClipboardPreviewScreenState extends State<ClipboardPreviewScreen>
    with WidgetsBindingObserver {
  ClipboardTextPreview? _preview;
  String _status = 'Clipboard is not read automatically.';
  bool _reading = false;
  int _readGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _preview = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _readGeneration++;
      if ((_preview != null || _reading) && mounted) {
        setState(() {
          _preview = null;
          _status =
              'Cleared the local preview when the app left the foreground.';
        });
      }
    }
  }

  Future<void> _read() async {
    if (_reading) return;
    final generation = ++_readGeneration;
    setState(() {
      _reading = true;
      _preview = null;
      _status = 'Reading clipboard text…';
    });
    try {
      final text = await const MethodChannel(
        'personal_assistant/clipboard_preview',
      ).invokeMethod<String?>('read_plain_text');
      final preview = ClipboardTextPreview.fromText(text);
      if (!mounted || generation != _readGeneration) return;
      setState(() {
        _preview = preview;
        _status = switch (preview) {
          null => 'The clipboard has no plain text to show. Other content was not read.',
          ClipboardTextPreview(truncated: true) =>
            'Showing a limited preview; the clipboard was not sent or saved.',
          _ => 'Showing clipboard text locally; it has not been sent or saved.',
        };
      });
    } catch (_) {
      if (!mounted || generation != _readGeneration) return;
      setState(() {
        _preview = null;
        _status = 'Could not read clipboard text; nothing was shown.';
      });
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  void _clear() {
    _readGeneration++;
    setState(() {
      _preview = null;
      _status = 'Cleared the local clipboard preview.';
    });
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Read clipboard text',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Only reads plain text after you tap. The preview stays on this device, is not sent to the assistant or saved, and clears when the app backgrounds or closes.',
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _reading ? null : _read,
                icon: const Icon(Icons.content_paste_outlined),
                label: Text(_reading ? 'Reading…' : 'Read clipboard'),
              ),
              if (_preview case final preview?) ...[
                const SizedBox(height: 12),
                SelectableText(preview.text),
              ],
              const SizedBox(height: 8),
              Text(_status, style: Theme.of(context).textTheme.bodySmall),
              if (_preview != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _clear,
                    icon: const Icon(Icons.clear),
                    label: const Text('Clear preview'),
                  ),
                ),
            ],
          ),
        ),
      ),
    ],
  );
}
