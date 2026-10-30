import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'assistant_state.dart';

bool isValidUserNotificationContent(String title, String text) {
  bool hasDisallowedControl(String value, {bool multiline = false}) => value
      .codeUnits
      .any((unit) =>
          (unit <= 0x1f || (unit >= 0x7f && unit <= 0x9f)) &&
          !(multiline && (unit == 0x09 || unit == 0x0a || unit == 0x0d)));

  return title.trim().isNotEmpty &&
      title.length <= 80 &&
      text.trim().isNotEmpty &&
      text.length <= 300 &&
      !hasDisallowedControl(title) &&
      !hasDisallowedControl(text, multiline: true);
}

/// A manually composed immediate notification, gated by an exact-content review.
/// It is not a reminder, persistent record, or Gemini-triggered action.
class UserNotificationScreen extends StatefulWidget {
  const UserNotificationScreen({super.key});

  @override
  State<UserNotificationScreen> createState() => _UserNotificationScreenState();
}

class _UserNotificationScreenState extends State<UserNotificationScreen> {
  final _title = TextEditingController();
  final _text = TextEditingController();
  bool _posting = false;
  String _status = 'Nothing is posted until you review and approve it.';

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _reviewAndPost() async {
    final title = _title.text;
    final text = _text.text;
    if (!isValidUserNotificationContent(title, text)) {
      setState(() => _status = 'Enter a non-empty title and text within the limits.');
      return;
    }
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Review notification'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Title: $title'),
              const SizedBox(height: 8),
              Text('Text: $text'),
              const SizedBox(height: 12),
              const Text('This posts immediately on this device. It is not a reminder or a saved message. Android notification permission is requested only after you approve.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Post notification'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;

    setState(() {
      _posting = true;
      _status = 'Requesting Android permission…';
    });
    try {
      final permission = await AssistantState.device
          .invokeMapMethod<String, Object?>('request_access_permission', {
            'permission': 'notifications',
          });
      if (permission?['granted'] != true) {
        if (mounted) setState(() => _status = 'Notification permission was not granted; nothing was posted.');
        return;
      }
      final response = await AssistantState.device
          .invokeMapMethod<String, Object?>('post_user_notification', {
            'title': title,
            'text': text,
          });
      if (!mounted) return;
      setState(() {
        _status = response?['posted'] == true
            ? 'Android accepted the notification request. Its display is not verified.'
            : 'Android did not confirm posting the notification.';
        if (response?['posted'] == true) {
          _title.clear();
          _text.clear();
        }
      });
    } on PlatformException catch (error) {
      if (mounted) setState(() => _status = error.message ?? 'Android could not post the notification.');
    } on MissingPluginException {
      if (mounted) setState(() => _status = 'Immediate notifications are available in the Android app only.');
    } catch (_) {
      if (mounted) setState(() => _status = 'Android did not confirm posting the notification.');
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text('Immediate notification', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      const Text('Create a one-time notification for this device. It is not saved, scheduled, sent to Gemini, or shared elsewhere.'),
      const SizedBox(height: 18),
      TextField(
        key: const Key('user-notification-title'),
        controller: _title,
        maxLength: 80,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Notification title', border: OutlineInputBorder()),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 8),
      TextField(
        key: const Key('user-notification-text'),
        controller: _text,
        maxLength: 300,
        minLines: 3,
        maxLines: 6,
        keyboardType: TextInputType.multiline,
        decoration: const InputDecoration(labelText: 'Notification text', border: OutlineInputBorder()),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 10),
      FilledButton.icon(
        key: const Key('review-user-notification'),
        onPressed: !_posting && isValidUserNotificationContent(_title.text, _text.text)
            ? _reviewAndPost
            : null,
        icon: _posting
            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.notifications_active_outlined),
        label: const Text('Review notification'),
      ),
      const SizedBox(height: 12),
      Text(_status, key: const Key('user-notification-status')),
    ],
  );
}
