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
  final _number = TextEditingController();
  String _kind = 'whatsapp';
  bool _opening = false;

  @override
  void dispose() {
    _text.dispose();
    _number.dispose();
    super.dispose();
  }

  Future<void> _openShareSheet() async {
    final body = _text.text;
    final number = _number.text.trim();
    final isWhatsApp = _kind == 'whatsapp';
    final validNumber = RegExp(r'^\+[1-9][0-9]{6,14}$').hasMatch(number);
    if (body.trim().isEmpty || _opening) return;
    if (isWhatsApp && (!validNumber || body.length > 1600)) return;
    if (!isWhatsApp && body.length > 10000) return;
    setState(() => _opening = true);
    try {
      final response = isWhatsApp
          ? await _device.invokeMethod<Object?>('open_whatsapp_draft', {
              'number': number,
              'message': body,
            })
          : await _device.invokeMethod<Object?>('share_text', {
              'title': 'Review social caption',
              'text': body,
            });
      if (isWhatsApp &&
          mounted &&
          response is Map &&
          response['result'] == 'handoff_opened') {
        notice(
          context,
          'Android accepted the WhatsApp-link handoff. Nothing was sent; review the draft and tap Send in WhatsApp.',
        );
      }
    } on PlatformException catch (error) {
      if (mounted) {
        notice(
          context,
          error.message ?? 'Android could not open the share sheet.',
        );
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
          Text(
            'Write it here, send it yourself',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Nothing is sent or published by this app. For WhatsApp, enter one full international number; Personal AI shows the exact recipient and message in an approval dialog before opening a prefilled link. You must tap Send in WhatsApp. Social captions open Android’s share sheet.',
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
                  decoration: const InputDecoration(labelText: 'Draft type'),
                  items: const [
                    DropdownMenuItem(
                      value: 'whatsapp',
                      child: Text('WhatsApp reply'),
                    ),
                    DropdownMenuItem(
                      value: 'social',
                      child: Text('Social post caption'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _kind = value ?? 'whatsapp'),
                ),
                if (_kind == 'whatsapp') ...[
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('outbound-draft-number'),
                    controller: _number,
                    keyboardType: TextInputType.phone,
                    maxLength: 16,
                    decoration: const InputDecoration(
                      labelText: 'International phone number',
                      hintText: '+<country code><number>',
                      helperText: 'Include + and the country code; no spaces.',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('outbound-draft-text'),
                  controller: _text,
                  minLines: 7,
                  maxLines: 14,
                  maxLength: _kind == 'whatsapp' ? 1600 : 10000,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: _kind == 'whatsapp'
                        ? 'Reply draft'
                        : 'Caption draft',
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
                    onPressed:
                        _text.text.trim().isEmpty ||
                            _opening ||
                            (_kind == 'whatsapp' &&
                                (!RegExp(r'^\+[1-9][0-9]{6,14}$')
                                        .hasMatch(_number.text.trim()) ||
                                    _text.text.length > 1600))
                        ? null
                        : _openShareSheet,
                    icon: _opening
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.ios_share_rounded),
                    label: Text(
                      _kind == 'whatsapp'
                          ? 'Review WhatsApp draft'
                          : 'Choose app to review caption',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Glass(
            child: Text(
              'WhatsApp requires a number you enter yourself and a separate approval step. The app never sends the message. Social sharing still does not choose a recipient, attach media, or publish a post. Drafts are not saved after you leave.',
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
  bool _running = false;

  Future<void> _pulse() async {
    if (_running) return;
    setState(() => _running = true);
    try {
      await HapticFeedback.vibrate();
      if (mounted) {
        notice(context, 'Requested one short haptic pulse.');
      }
    } on PlatformException {
      if (mounted) {
        notice(context, 'This device did not provide haptic feedback.');
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
      'Tap to request one short pulse. Android may ignore it if vibration is unavailable or disabled.',
    ),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: _running ? null : _pulse,
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
