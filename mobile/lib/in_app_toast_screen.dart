import 'package:flutter/material.dart';

const int maxInAppToastCodePoints = 120;

/// Accepts only short, non-empty text without control characters.
bool isValidInAppToastText(String text) {
  final runes = text.runes;
  if (text.trim().isEmpty || runes.length > maxInAppToastCodePoints) {
    return false;
  }
  return runes.every(
    (rune) => rune >= 0x20 && !(rune >= 0x7f && rune <= 0x9f),
  );
}

/// A manually entered, confirmation-gated transient in-app message.
/// It is not a system notification and the text is not persisted.
class InAppToastScreen extends StatefulWidget {
  const InAppToastScreen({super.key});

  @override
  State<InAppToastScreen> createState() => _InAppToastScreenState();
}

class _InAppToastScreenState extends State<InAppToastScreen> {
  final _text = TextEditingController();
  bool _reviewing = false;
  String? _status;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _reviewAndShow() async {
    final message = _text.text;
    if (_reviewing || !isValidInAppToastText(message)) return;
    setState(() {
      _reviewing = true;
      _status = null;
    });
    try {
      final approved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Review in-app message'),
          content: SelectableText(message),
          actions: [
            TextButton(
              key: const ValueKey('cancel-in-app-toast'),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              key: const ValueKey('confirm-in-app-toast'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Show in app'),
            ),
          ],
        ),
      );
      if (approved != true || !mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) {
        setState(() => _status = 'Could not show the in-app message.');
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      setState(() => _status = 'Shown briefly in this app only.');
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final valid = isValidInAppToastText(_text.text);
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('In-app toast')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Show a short message',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Enter the exact text, review it, then choose Show in app. It appears briefly in Personal AI only; it is not a notification and is not saved.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('in-app-toast-text'),
            controller: _text,
            maxLength: maxInAppToastCodePoints,
            maxLines: 3,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Message text',
              hintText: 'A short message to show in the app',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() => _status = null),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const ValueKey('review-in-app-toast'),
            onPressed: valid && !_reviewing ? _reviewAndShow : null,
            // The review dialog is modal, so an indeterminate spinner under it
            // would keep widget tests (and screen readers) in a false loading state.
            icon: const Icon(Icons.message_outlined),
            label: Text(_reviewing ? 'Reviewing…' : 'Review message'),
          ),
          if (_status case final status?) ...[
            const SizedBox(height: 12),
            Text(status, key: const ValueKey('in-app-toast-status')),
          ],
        ],
      ),
    );
  }
}
