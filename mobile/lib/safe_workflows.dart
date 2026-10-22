import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'assistant_state.dart';
import 'main.dart' show Glass, Home, Shell, notice;

/// User-edited text handed to Android's chooser only after an explicit tap.
class OutboundDraftsScreen extends StatefulWidget {
  const OutboundDraftsScreen({super.key});

  @override
  State<OutboundDraftsScreen> createState() => _OutboundDraftsScreenState();
}

class _OutboundDraftsScreenState extends State<OutboundDraftsScreen> {
  static const _device = MethodChannel('personal_assistant/device');
  final _text = TextEditingController();
  String _kind = 'whatsapp';
  bool _opening = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _openShareSheet() async {
    final body = _text.text.trim();
    if (body.isEmpty || body.length > 10000 || _opening) return;
    setState(() => _opening = true);
    try {
      await _device.invokeMethod<Object?>('share_text', {
        'title': _kind == 'whatsapp' ? 'Review WhatsApp reply' : 'Review social caption',
        'text': body,
      });
    } on PlatformException catch (error) {
      if (mounted) notice(context, error.message ?? 'Android could not open the share sheet.');
    } on MissingPluginException {
      if (mounted) notice(context, 'Text sharing is available in the Android app only.');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Shell(
      title: 'Message & social drafts',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 118),
        children: [
          Text('Write it here, send it yourself', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Nothing is sent or published by this app. Continue opens Android’s share sheet; choose the app and conversation, then review and send there.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          Glass(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _kind,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Draft type'),
                  items: const [
                    DropdownMenuItem(value: 'whatsapp', child: Text('WhatsApp reply')),
                    DropdownMenuItem(value: 'social', child: Text('Social post caption')),
                  ],
                  onChanged: (value) => setState(() => _kind = value ?? 'whatsapp'),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('outbound-draft-text'),
                  controller: _text,
                  minLines: 7,
                  maxLines: 14,
                  maxLength: 10000,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: _kind == 'whatsapp' ? 'Reply draft' : 'Caption draft',
                    hintText: _kind == 'whatsapp'
                        ? 'Write a reply to review in your messaging app…'
                        : 'Write a caption to review in your social app…',
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _text.text.trim().isEmpty || _opening ? null : _openShareSheet,
                    icon: _opening
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.ios_share_rounded),
                    label: Text(_kind == 'whatsapp' ? 'Choose app to review reply' : 'Choose app to review caption'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Glass(
            child: Text(
              'This shares text only. It does not connect to your accounts, choose a recipient, attach media, send messages, or publish posts. Draft text stays in this screen and is not saved after you leave.',
            ),
          ),
        ],
      ),
    );
  }
}

/// First-party skills are limited to the already-reviewed local actions.
class SafeSkillsScreen extends StatelessWidget {
  final AssistantState state;
  const SafeSkillsScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context) => Shell(
    title: 'Skills & actions',
    assistantName: state.assistantName,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 118),
      children: [
        Text('Small, explicit workflows', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'Each action starts only when you tap it and asks for approval before it runs. Android app launches come only from the live installed-app picker; reminders use Android notifications.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Glass(
          child: Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.school_outlined),
                title: const Text('Open a study app'),
                subtitle: const Text('Pick an installed app, review its name, then approve the launch.'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Home(state: state).openAppPicker(context),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.notifications_active_outlined),
                title: const Text('Prepare a study reminder'),
                subtitle: const Text('Choose its wording and time, then approve the reminder.'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Home(state: state).reminder(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Glass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sub-agent execution isn’t available yet', style: TextStyle(fontWeight: FontWeight.w700)),
              SizedBox(height: 6),
              Text('This app can discover MCP tool names, but it does not invoke them or delegate chat work. There is no background workflow runner, and no AccessibilityService, screen capture, shell command or blanket device-control permission is enabled.'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => Navigator.pushNamed(context, '/automations'),
          icon: const Icon(Icons.receipt_long_outlined),
          label: const Text('Review action history'),
        ),
      ],
    ),
  );
}
