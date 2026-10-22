import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'assistant_state.dart';
import 'multi_agent_workflow.dart';
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
      if (mounted) {
        notice(context, error.message ?? 'Android could not open the share sheet.');
      }
    } on MissingPluginException {
      if (mounted) {
        notice(context, 'Text sharing is available in the Android app only.');
      }
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
              const Divider(),
              ListTile(
                key: const ValueKey('multi-agent-workflow-entry'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.hub_outlined),
                title: const Text('Try a multi-agent workflow'),
                subtitle: const Text('A reviewed, four-pass team using your selected online model.'),
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
              Text('What the team can and can’t do', style: TextStyle(fontWeight: FontWeight.w700)),
              SizedBox(height: 6),
              Text('The workflow runs four sequential roles—planner, specialist, reviewer and synthesizer—through the same configured online model. It is not a parallel swarm or independent models. It has no tools, memory, chat history, files or permission to execute actions; you review the result yourself. MCP tool discovery remains display-only.'),
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
  bool _running = false;
  String _progress = '';
  String _error = '';

  @override
  void dispose() {
    if (_running) _runner.cancel();
    _task.dispose();
    super.dispose();
  }

  Future<void> _reviewAndRun() async {
    final goal = _task.text.trim();
    final config = widget.state.config;
    try {
      _runner.validate(config, goal);
    } catch (error) {
      setState(() => _error = error.toString());
      return;
    }
    final providerHost = Uri.parse(config.origin).host;
    final approved =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Review the four-pass run'),
            scrollable: true,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Same online model: ${config.model}'),
                Text('Provider: $providerHost'),
                const SizedBox(height: 12),
                const Text(
                  'Passes run in order: planner → specialist → reviewer → synthesizer.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'The first request contains your task and fixed role instructions. Each later request also includes the earlier model outputs. This can use API credits, and the provider may retain submitted text. Chat history, saved memory and files are not added. Don’t put passwords, API keys or verification codes in the task; the configured API key is sent only as the provider’s authentication header. No tools or external actions are included.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'All four passes use the same model; this is not parallel or independent agents. Nothing the model suggests is executed automatically.',
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
                child: const Text('Run four passes'),
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
        onPassStarted: (role, index) {
          if (mounted) setState(() => _progress = 'Pass $index of 4 · $role');
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
            'Planner, specialist, reviewer and synthesizer run one after another using the same configured OpenAI-compatible model. Each pass sees your task and prior pass outputs. This is a bounded multi-role workflow, not separate models or a parallel swarm.',
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
                TextField(
                  key: const ValueKey('multi-agent-task'),
                  controller: _task,
                  minLines: 4,
                  maxLines: 9,
                  maxLength: MultiAgentWorkflowRunner.maxGoalCharacters,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Task for the team',
                    hintText: 'Describe one task for the four passes…',
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
                      label: const Text('Review & run four passes'),
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
