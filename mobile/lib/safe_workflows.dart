import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'assistant_state.dart';
import 'multi_agent_workflow.dart';
import 'circuit_guide.dart';
import 'main.dart' show Glass, Home, Shell, notice;

/// User-entered phone and social drafts require a deliberate handoff.
class OutboundDraftsScreen extends StatefulWidget {
  const OutboundDraftsScreen({super.key});

  @override
  State<OutboundDraftsScreen> createState() => _OutboundDraftsScreenState();
}

class _OutboundDraftsScreenState extends State<OutboundDraftsScreen> {
  static const _device = MethodChannel('personal_assistant/device');
  final _text = TextEditingController();
  final _number = TextEditingController();
  final _recipient = TextEditingController();
  final _subject = TextEditingController();
  String _kind = 'whatsapp';
  bool _opening = false;

  bool get _needsNumber => _kind != 'social' && _kind != 'email';
  bool get _needsRecipient => _kind == 'email';
  bool get _needsSubject => _kind == 'email';
  bool get _needsText => _kind != 'phone';
  bool get _isWhatsApp => _kind == 'whatsapp';
  bool get _isSms => _kind == 'sms';
  int get _textLimit => _kind == 'social' || _kind == 'email' ? 10000 : 1600;
  bool get _hasValidRecipient => RegExp(
    r"""^[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+)*@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$""",
  ).hasMatch(_recipient.text.trim());
  bool get _hasValidNumber =>
      RegExp(r'^\+[1-9][0-9]{6,14}$').hasMatch(_number.text.trim());
  bool get _canSubmit =>
      !_opening &&
      (!_needsNumber || _hasValidNumber) &&
      (!_needsRecipient || _hasValidRecipient) &&
      (!_needsSubject ||
          (_subject.text.length <= 200 &&
              !_subject.text.contains(RegExp(r'[\x00-\x1f\x7f]')))) &&
      (!_needsText ||
          (_text.text.trim().isNotEmpty && _text.text.length <= _textLimit));

  @override
  void dispose() {
    _text.dispose();
    _number.dispose();
    _recipient.dispose();
    _subject.dispose();
    super.dispose();
  }

  String get _buttonLabel => switch (_kind) {
    'whatsapp' => 'Review WhatsApp draft',
    'sms' => 'Review SMS draft',
    'phone' => 'Review number in dialer',
    'email' => 'Review email draft',
    _ => 'Choose app to review caption',
  };

  Future<void> _openHandoff() async {
    if (!_canSubmit) return;
    final number = _number.text.trim();
    final body = _text.text;
    final recipient = _recipient.text.trim();
    final subject = _subject.text;
    setState(() => _opening = true);
    try {
      final response = switch (_kind) {
        'whatsapp' => await _device.invokeMethod<Object?>(
          'open_whatsapp_draft',
          {'number': number, 'message': body},
        ),
        'sms' => await _device.invokeMethod<Object?>('open_sms_draft', {
          'number': number,
          'message': body,
        }),
        'phone' => await _device.invokeMethod<Object?>('open_phone_dialer', {
          'number': number,
        }),
        'email' => await _device.invokeMethod<Object?>('open_email_draft', {
          'recipient': recipient,
          'subject': subject,
          'body': body,
        }),
        _ => await _device.invokeMethod<Object?>('share_text', {
          'title': 'Review social caption',
          'text': body,
        }),
      };
      if (!mounted || response is! Map) return;
      final result = response['result'];
      if (_kind == 'whatsapp' && result == 'handoff_opened') {
        notice(
          context,
          'WhatsApp opened with the draft. Nothing was sent; tap Send there if you choose.',
        );
      } else if (_isSms && result == 'composer_opened') {
        notice(
          context,
          'Your messaging app opened with the draft. Nothing was sent.',
        );
      } else if (_kind == 'phone' && result == 'dialer_opened') {
        notice(context, 'Android opened the dialer. No call was placed.');
      } else if (_kind == 'email' && result == 'composer_opened') {
        notice(
          context,
          'Your email app opened with the draft. Nothing was sent.',
        );
      }
    } on PlatformException catch (error) {
      if (mounted) {
        notice(
          context,
          error.message ?? 'Android could not open that handoff.',
        );
      }
    } on MissingPluginException {
      if (mounted) {
        notice(
          context,
          'Phone, email and text handoffs are available in the Android app only.',
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Shell(
      title: 'Phone & message drafts',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 118),
        children: [
          Text(
            'Prepare it here, finish it yourself',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Phone numbers and message text stay in this screen until you choose a handoff. Email, SMS and WhatsApp show the exact recipient and draft for approval first; Android opens the dialer for calls. Nothing is sent or called automatically.',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          Glass(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _kind,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Handoff'),
                  items: const [
                    DropdownMenuItem(
                      value: 'whatsapp',
                      child: Text('WhatsApp draft'),
                    ),
                    DropdownMenuItem(value: 'sms', child: Text('SMS draft')),
                    DropdownMenuItem(
                      value: 'email',
                      child: Text('Email draft'),
                    ),
                    DropdownMenuItem(
                      value: 'phone',
                      child: Text('Phone dialer'),
                    ),
                    DropdownMenuItem(
                      value: 'social',
                      child: Text('Social post caption'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _kind = value ?? 'whatsapp'),
                ),
                if (_needsRecipient) ...[
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('outbound-draft-recipient'),
                    controller: _recipient,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email recipient',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('outbound-draft-subject'),
                    controller: _subject,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      labelText: 'Subject (optional)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
                if (_needsNumber) ...[
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('outbound-draft-number'),
                    controller: _number,
                    keyboardType: TextInputType.phone,
                    maxLength: 16,
                    decoration: InputDecoration(
                      labelText: 'International phone number',
                      hintText: '+<country code><number>',
                      helperText: 'Include + and the country code; no spaces.',
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
                if (_needsText) ...[
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('outbound-draft-text'),
                    controller: _text,
                    minLines: 4,
                    maxLines: 14,
                    maxLength: _textLimit,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: _kind == 'email'
                          ? 'Email message'
                          : _isWhatsApp
                          ? 'WhatsApp message'
                          : _isSms
                          ? 'SMS message'
                          : 'Caption draft',
                      hintText: _kind == 'email'
                          ? 'Write an email to review in your email app…'
                          : _isWhatsApp
                          ? 'Write a reply to review in WhatsApp…'
                          : _isSms
                          ? 'Write a text message to review in your messaging app…'
                          : 'Write a caption to review in your social app…',
                      alignLabelWithHint: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const ValueKey('review-outbound-handoff'),
                    onPressed: _canSubmit ? _openHandoff : null,
                    icon: _opening
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.ios_share_rounded),
                    label: Text(_buttonLabel),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Glass(
            child: Text(
              'Android asks you to review each recipient and draft before opening an email, messaging app or dialer. It never sends a message or places a call for you. Social sharing does not choose a recipient or publish a post. Drafts are not saved after you leave.',
            ),
          ),
        ],
      ),
    );
  }
}

/// A user-entered destination is reviewed by Android before Maps is opened.
class MapSearchAction extends StatefulWidget {
  const MapSearchAction({super.key});

  @override
  State<MapSearchAction> createState() => _MapSearchActionState();
}

class _MapSearchActionState extends State<MapSearchAction> {
  static const _device = MethodChannel('personal_assistant/device');
  final _destination = TextEditingController();
  bool _opening = false;

  @override
  void dispose() {
    _destination.dispose();
    super.dispose();
  }

  Future<void> _reviewAndOpen() async {
    final destination = _destination.text.trim();
    if (_opening ||
        destination.isEmpty ||
        destination.length > 120 ||
        destination.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      return;
    }
    setState(() => _opening = true);
    try {
      final response = await _device.invokeMethod<Object?>('open_map_search', {
        'destination': destination,
      });
      if (mounted && response is Map && response['result'] == 'opened_search') {
        notice(
          context,
          'Android opened a map search. Choose what to do there; navigation has not started.',
        );
      }
    } on PlatformException catch (error) {
      if (mounted) {
        notice(
          context,
          error.message ?? 'Android could not open a map search.',
        );
      }
    } on MissingPluginException {
      if (mounted) {
        notice(context, 'Map search is available in the Android app only.');
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = _destination.text.trim();
    final valid =
        value.isNotEmpty &&
        value.length <= 120 &&
        !value.contains(RegExp(r'[\x00-\x1f\x7f]'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey('map-search-destination'),
          controller: _destination,
          maxLength: 120,
          decoration: const InputDecoration(
            labelText: 'Place or address',
            hintText: 'Enter a destination to search in Maps',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const ValueKey('review-map-search'),
          onPressed: valid && !_opening ? _reviewAndOpen : null,
          icon: _opening
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.map_outlined),
          label: const Text('Review and open Maps'),
        ),
        const SizedBox(height: 8),
        Text(
          'Android shows the exact destination for approval first. It opens a map search only; no location is read and navigation does not start automatically.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// This action begins only from a user's tap; Android shows a separate approval
/// dialog before it requests camera permission or changes the torch state.
class TorchOffAction extends StatefulWidget {
  const TorchOffAction({super.key});

  @override
  State<TorchOffAction> createState() => _TorchOffActionState();
}

class _TorchOffActionState extends State<TorchOffAction> {
  static const _device = MethodChannel('personal_assistant/device');
  bool _running = false;

  Future<void> _reviewTorchOff() async {
    if (_running) return;
    setState(() => _running = true);
    try {
      final response = await _device.invokeMethod<Object?>('turn_torch_off');
      if (!mounted || response is! Map) return;
      if (response['result'] == 'confirmed_off') {
        notice(context, 'Android confirmed the flashlight is off.');
      }
    } on PlatformException catch (error) {
      if (mounted) {
        notice(
          context,
          error.message ?? 'Android could not confirm the flashlight is off.',
        );
      }
    } on MissingPluginException {
      if (mounted) {
        notice(
          context,
          'Flashlight control is available in the Android app only.',
        );
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
    key: const ValueKey('torch-off-action'),
    contentPadding: EdgeInsets.zero,
    leading: _running
        ? const SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.flashlight_off_outlined),
    title: const Text('Turn flashlight off'),
    subtitle: const Text(
      'Android asks for approval first; camera permission is requested only if needed.',
    ),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: _running ? null : _reviewTorchOff,
  );
}

/// A user-started haptic test, adapted from MYRA's bounded vibration action.
class HapticPulseAction extends StatefulWidget {
  const HapticPulseAction({super.key});

  @override
  State<HapticPulseAction> createState() => _HapticPulseActionState();
}

class _HapticPulseActionState extends State<HapticPulseAction> {
  static const _device = MethodChannel('personal_assistant/device');
  bool _running = false;

  Future<void> _pulse() async {
    if (_running) return;
    setState(() => _running = true);
    try {
      final outcome = await _device.invokeMapMethod<String, dynamic>(
        'request_haptic_pulse',
      );
      if (mounted && outcome?['requested'] == true) {
        notice(
          context,
          'Android accepted one 80 ms vibration request; the physical effect is not confirmed.',
        );
      } else if (mounted && outcome == null) {
        notice(context, 'Android did not confirm the vibration request.');
      }
    } on PlatformException catch (error) {
      if (mounted) {
        notice(context, error.message ?? 'Haptic feedback is unavailable.');
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
    key: const ValueKey('haptic-pulse-action'),
    contentPadding: EdgeInsets.zero,
    leading: _running
        ? const SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.vibration_outlined),
    title: const Text('Test haptic feedback'),
    subtitle: const Text(
      'Android shows a confirmation before requesting one fixed 80 ms pulse. It may be ignored if unavailable or disabled.',
    ),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: _running ? null : _pulse,
  );
}

/// Copies only user-entered text, after a full-text review and explicit approval.
class CopyTextAction extends StatefulWidget {
  const CopyTextAction({super.key});

  @override
  State<CopyTextAction> createState() => _CopyTextActionState();
}

class _CopyTextActionState extends State<CopyTextAction> {
  final _text = TextEditingController();
  bool _copying = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _reviewAndCopy() async {
    final exactText = _text.text;
    if (_copying || exactText.isEmpty || exactText.length > 4000) return;
    final approved =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Review clipboard text'),
            scrollable: true,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Copy this exact text to Android’s clipboard?'),
                const SizedBox(height: 12),
                SelectableText(
                  exactText,
                  key: const ValueKey('clipboard-review-text'),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Other apps may be able to read clipboard contents. Personal AI will not save this text.',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const ValueKey('approve-clipboard-copy'),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Copy this text'),
              ),
            ],
          ),
        ) ??
        false;
    if (!approved || !mounted) return;
    setState(() => _copying = true);
    try {
      await Clipboard.setData(ClipboardData(text: exactText));
      if (mounted) {
        notice(context, 'Copied the reviewed text to the clipboard.');
      }
    } on PlatformException {
      if (mounted) notice(context, 'Android could not copy the text.');
    } on MissingPluginException {
      if (mounted) {
        notice(context, 'Clipboard copy is available on Android only.');
      }
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        key: const ValueKey('clipboard-copy-text'),
        controller: _text,
        maxLength: 4000,
        maxLines: 4,
        decoration: const InputDecoration(
          labelText: 'Text to copy',
          hintText: 'Enter the exact text you want on your clipboard',
          border: OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() {}),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          key: const ValueKey('review-clipboard-copy'),
          onPressed:
              _text.text.isNotEmpty && _text.text.length <= 4000 && !_copying
              ? _reviewAndCopy
              : null,
          icon: const Icon(Icons.content_copy_rounded),
          label: const Text('Review and copy text'),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        'Nothing is copied until you approve the exact text. Other apps may read clipboard contents.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}

/// Applies a reviewed temporary brightness level to this app's window only.
class TemporaryBrightnessAction extends StatefulWidget {
  const TemporaryBrightnessAction({super.key});

  @override
  State<TemporaryBrightnessAction> createState() =>
      _TemporaryBrightnessActionState();
}

class _TemporaryBrightnessActionState extends State<TemporaryBrightnessAction>
    with WidgetsBindingObserver {
  static const _device = MethodChannel('personal_assistant/device');
  int _level = 128;
  bool _active = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (mounted && _active) setState(() => _active = false);
    }
  }

  Future<void> _apply() async {
    if (_busy) return;
    final selected = _level;
    final approved =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Review temporary brightness'),
            content: Text(
              'Set this app window to brightness $selected of 255? The rest of your screen is unchanged. Android’s original setting will be restored when Personal AI leaves the foreground.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const ValueKey('approve-temporary-brightness'),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Apply to this app'),
              ),
            ],
          ),
        ) ??
        false;
    if (!approved || !mounted) return;
    setState(() => _busy = true);
    try {
      await _device.invokeMethod<Object?>('set_temporary_brightness', {
        'level': selected,
      });
      if (mounted) {
        setState(() => _active = true);
        notice(context, 'Applied brightness $selected to Personal AI only.');
      }
    } on PlatformException catch (error) {
      if (mounted) {
        notice(context, error.message ?? 'Could not change brightness.');
      }
    } on MissingPluginException {
      if (mounted) {
        notice(context, 'Temporary brightness is available on Android only.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    if (_busy || !_active) return;
    setState(() => _busy = true);
    try {
      await _device.invokeMethod<Object?>('restore_temporary_brightness');
      if (mounted) {
        setState(() => _active = false);
        notice(context, 'Restored the original app brightness.');
      }
    } on PlatformException catch (error) {
      if (mounted) {
        notice(context, error.message ?? 'Could not restore brightness.');
      }
    } on MissingPluginException {
      if (mounted) {
        notice(context, 'Temporary brightness is available on Android only.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.brightness_6_outlined),
        title: const Text('Temporary app brightness'),
        subtitle: const Text(
          'Choose a level for this app only; Android restores the prior setting when you leave it.',
        ),
      ),
      Slider(
        key: const ValueKey('temporary-brightness-slider'),
        value: _level.toDouble(),
        min: 0,
        max: 255,
        divisions: 255,
        label: '$_level',
        onChanged: _busy
            ? null
            : (value) => setState(() => _level = value.round()),
      ),
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          Text('$_level / 255'),
          if (_active)
            TextButton(
              key: const ValueKey('restore-temporary-brightness'),
              onPressed: _busy ? null : _restore,
              child: const Text('Restore now'),
            ),
          FilledButton.tonal(
            key: const ValueKey('review-temporary-brightness'),
            onPressed: _busy ? null : _apply,
            child: const Text('Review level'),
          ),
        ],
      ),
      Text(
        'The exact level is shown before applying. This does not change Android’s system-wide brightness.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
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
        Text(
          'Small, explicit workflows',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Each action starts only when you tap it and asks for approval before it runs. Android app launches come only from the live installed-app picker; reminders use Android notifications.',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Glass(
          child: Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.school_outlined),
                title: const Text('Open a study app'),
                subtitle: const Text(
                  'Pick an installed app, review its name, then approve the launch.',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Home(state: state).openAppPicker(context),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.notifications_active_outlined),
                title: const Text('Prepare a study reminder'),
                subtitle: const Text(
                  'Choose its wording and time, then approve the reminder.',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Home(state: state).reminder(context),
              ),
              const Divider(),
              const MapSearchAction(),
              const Divider(),
              const TorchOffAction(),
              const Divider(),
              const HapticPulseAction(),
              const Divider(),
              const TemporaryBrightnessAction(),
              const Divider(),
              const CopyTextAction(),
              const Divider(),
              ListTile(
                key: const ValueKey('circuit-guide-entry'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.electric_bolt_outlined),
                title: const Text('Circuit guide'),
                subtitle: const Text(
                  'Learn basic Ohm’s law and resistor combinations with a local calculator.',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const CircuitGuideScreen()),
                ),
              ),
              const Divider(),
              ListTile(
                key: const ValueKey('multi-agent-workflow-entry'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.hub_outlined),
                title: const Text('Try a multi-agent workflow'),
                subtitle: const Text(
                  'A reviewed, configurable sequence using your selected online model.',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MultiAgentWorkflowScreen(state: state),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Glass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'What the team can and can’t do',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 6),
              Text(
                'By default it runs planner, specialist, reviewer and synthesizer in sequence through the same configured online model. You can reorder or remove the planner and specialist; reviewer and synthesizer stay required. It is not a parallel swarm or independent models, and has no tools, memory, chat history, files or permission to execute actions. You review the result yourself; MCP tool discovery remains display-only.',
              ),
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

/// A user-started, approval-gated sequence of role-specific model passes.
class MultiAgentWorkflowScreen extends StatefulWidget {
  final AssistantState state;
  const MultiAgentWorkflowScreen({super.key, required this.state});

  @override
  State<MultiAgentWorkflowScreen> createState() =>
      _MultiAgentWorkflowScreenState();
}

class _MultiAgentWorkflowScreenState extends State<MultiAgentWorkflowScreen> {
  final _task = TextEditingController();
  late final MultiAgentWorkflowRunner _runner = MultiAgentWorkflowRunner(
    widget.state.clientFactory,
  );
  List<AgentPassResult> _passes = const [];
  List<String> _stepIds = List.of(MultiAgentWorkflowRunner.defaultStepIds);
  bool _running = false;
  String _progress = '';
  String _error = '';

  @override
  void dispose() {
    if (_running) _runner.cancel();
    _task.dispose();
    super.dispose();
  }

  void _moveStep(int index, int delta) {
    final destination = index + delta;
    if (_running ||
        destination < 0 ||
        destination >= _stepIds.length ||
        _stepIds[destination] == 'synthesizer') {
      return;
    }
    setState(() {
      final next = List<String>.of(_stepIds);
      final value = next.removeAt(index);
      next.insert(destination, value);
      if (MultiAgentWorkflowRunner.validStepOrder(next)) _stepIds = next;
      _passes = const [];
      _error = '';
    });
  }

  void _removeStep(String id) {
    if (_running || !MultiAgentWorkflowRunner.canRemoveStep(id)) return;
    setState(() {
      _stepIds.remove(id);
      _passes = const [];
      _error = '';
    });
  }

  void _restoreStep(String id) {
    if (_running || _stepIds.contains(id)) return;
    setState(() {
      if (id == 'synthesizer') {
        _stepIds.add(id);
      } else {
        final finalIndex = _stepIds.indexOf('synthesizer');
        _stepIds.insert(finalIndex < 0 ? _stepIds.length : finalIndex, id);
      }
      _passes = const [];
      _error = '';
    });
  }

  Future<void> _reviewAndRun() async {
    final goal = _task.text.trim();
    final config = widget.state.config;
    try {
      _runner.validate(config, goal, stepIds: _stepIds);
    } catch (error) {
      setState(() => _error = error.toString());
      return;
    }
    final providerHost = Uri.parse(config.origin).host;
    final approved =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('Review the ${_stepIds.length}-step run'),
            scrollable: true,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Same online model: ${config.model}'),
                Text('Provider: $providerHost'),
                const SizedBox(height: 12),
                Text(
                  'Steps run in order: ${_stepIds.map((id) => MultiAgentWorkflowRunner.stepForId(id).name).join(' → ')}.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'The first request contains your task and fixed role instructions. Each later request also includes the earlier model outputs. This can use API credits, and the provider may retain submitted text. Chat history, saved memory and files are not added. Don’t put passwords, API keys or verification codes in the task; the configured API key is sent only as the provider’s authentication header. No tools or external actions are included.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'All steps use the same model; this is not parallel or independent agents. The reviewer and final synthesizer remain required. Nothing the model suggests is executed automatically.',
                ),
                const SizedBox(height: 12),
                const Text('Exact task to send:'),
                const SizedBox(height: 6),
                SelectableText(goal),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text('Run ${_stepIds.length} steps'),
              ),
            ],
          ),
        ) ??
        false;
    if (!approved || !mounted) return;

    setState(() {
      _running = true;
      _passes = const [];
      _error = '';
      _progress = 'Starting…';
    });
    try {
      final result = await _runner.run(
        config: config,
        goal: goal,
        approvedThisRun: true,
        stepIds: List.unmodifiable(_stepIds),
        onPassStarted: (role, index) {
          if (mounted) {
            setState(
              () => _progress = 'Step $index of ${_stepIds.length} · $role',
            );
          }
        },
      );
      if (mounted) setState(() => _passes = result.passes);
    } on MultiAgentWorkflowException catch (error) {
      if (mounted) {
        setState(() {
          _passes = error.completedPasses;
          _error = error.message;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _progress = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.state.config;
    final ready =
        config.mode == 'compatible' &&
        config.token.isNotEmpty &&
        config.model.trim().isNotEmpty;
    return Shell(
      title: 'Multi-agent workflow',
      assistantName: widget.state.assistantName,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 118),
        children: [
          Text(
            'A small team, one model',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose the order and optional steps for a bounded workflow. The reviewer and final synthesizer stay required; every step uses the same configured OpenAI-compatible model, one after another. Each sees your task and prior outputs, not separate models or a parallel swarm.',
          ),
          const SizedBox(height: 14),
          const Glass(
            child: Text(
              'No tools or actions are available to the model. It does not get your chat history, saved memories or files. The app does not save the result or take actions; the reviewed task and earlier outputs are sent to the configured provider. Review any suggestions yourself.',
            ),
          ),
          const SizedBox(height: 14),
          Glass(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Workflow steps',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                for (var i = 0; i < _stepIds.length; i++)
                  ListTile(
                    key: ValueKey('workflow-step-${_stepIds[i]}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: IconButton(
                      tooltip:
                          'Move ${MultiAgentWorkflowRunner.stepForId(_stepIds[i]).name} up',
                      onPressed: !_running && i > 0
                          ? () => _moveStep(i, -1)
                          : null,
                      icon: const Icon(Icons.arrow_upward),
                    ),
                    title: Text(
                      MultiAgentWorkflowRunner.stepForId(_stepIds[i]).name,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip:
                              'Move ${MultiAgentWorkflowRunner.stepForId(_stepIds[i]).name} down',
                          onPressed:
                              !_running &&
                                  i < _stepIds.length - 1 &&
                                  _stepIds[i] != 'reviewer'
                              ? () => _moveStep(i, 1)
                              : null,
                          icon: const Icon(Icons.arrow_downward),
                        ),
                        if (MultiAgentWorkflowRunner.canRemoveStep(_stepIds[i]))
                          IconButton(
                            tooltip:
                                'Remove ${MultiAgentWorkflowRunner.stepForId(_stepIds[i]).name}',
                            onPressed: !_running
                                ? () => _removeStep(_stepIds[i])
                                : null,
                            icon: const Icon(Icons.remove_circle_outline),
                          )
                        else
                          const SizedBox(width: 48),
                      ],
                    ),
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final step
                        in MultiAgentWorkflowRunner.availableSteps.where(
                          (step) =>
                              !_stepIds.contains(step.id) &&
                              MultiAgentWorkflowRunner.canRemoveStep(step.id),
                        ))
                      ActionChip(
                        label: Text('Add ${step.name}'),
                        onPressed: !_running
                            ? () => _restoreStep(step.id)
                            : null,
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const ValueKey('multi-agent-task'),
                  controller: _task,
                  minLines: 4,
                  maxLines: 9,
                  maxLength: MultiAgentWorkflowRunner.maxGoalCharacters,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Task for the team',
                    hintText: 'Describe one task for the workflow…',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                  readOnly: _running,
                  onChanged: (_) => setState(() {
                    _error = '';
                    _passes = const [];
                  }),
                ),
                const SizedBox(height: 8),
                if (!ready)
                  const Text(
                    'Select and configure an OpenAI-compatible online model in Settings. Offline Gemma and the private FastAPI service are not supported by this first version.',
                  ),
                if (_error.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                if (_running) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_progress)),
                      TextButton(
                        onPressed: _runner.cancel,
                        child: const Text('Stop'),
                      ),
                    ],
                  ),
                ] else ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const ValueKey('review-multi-agent-run'),
                      onPressed: ready && _task.text.trim().isNotEmpty
                          ? _reviewAndRun
                          : null,
                      icon: const Icon(Icons.hub_outlined),
                      label: Text('Review & run ${_stepIds.length} steps'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_passes.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Team notes', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            for (final pass in _passes)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Glass(
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    initiallyExpanded: pass.role == 'Synthesizer',
                    title: Text(pass.role),
                    subtitle: Text(
                      '${pass.text.length} characters · model output, not verified',
                    ),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText(pass.text),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
