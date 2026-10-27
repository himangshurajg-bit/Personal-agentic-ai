import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'assistant_state.dart';
import 'system_clock_timer.dart';

/// Opens Android's Clock timer setup screen. The user must start the timer there.
class SystemClockTimerScreen extends StatefulWidget {
  const SystemClockTimerScreen({super.key});

  @override
  State<SystemClockTimerScreen> createState() => _SystemClockTimerScreenState();
}

class _SystemClockTimerScreenState extends State<SystemClockTimerScreen> {
  final _seconds = TextEditingController();
  final _label = TextEditingController();
  String? _error;
  String? _notice;
  bool _opening = false;

  @override
  void dispose() {
    _seconds.dispose();
    _label.dispose();
    super.dispose();
  }

  Future<void> _openClock() async {
    final request = parseSystemClockTimerRequest(_seconds.text, _label.text);
    if (request == null) {
      setState(() {
        _error =
            'Enter 1–86,400 whole seconds and a label up to 40 characters.';
        _notice = null;
      });
      return;
    }
    setState(() {
      _error = null;
      _notice = null;
      _opening = true;
    });
    try {
      await AssistantState.device.invokeMethod<void>('set_system_timer', {
        'seconds': request.seconds,
        'label': request.label,
      });
      if (mounted) {
        setState(
          () => _notice = 'Clock opened. Review and start the timer there.',
        );
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.message ?? 'Android could not open Clock.',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Android could not open Clock.');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text('System Clock timer', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      const Text(
        'Set a duration and open Android Clock. The timer will not start until you start it in Clock.',
      ),
      const SizedBox(height: 20),
      TextField(
        key: const Key('system-clock-seconds'),
        controller: _seconds,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(
          labelText: 'Duration (seconds)',
          hintText: 'For example, 300',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 14),
      TextField(
        key: const Key('system-clock-label'),
        controller: _label,
        maxLength: maxSystemClockTimerLabelLength,
        decoration: const InputDecoration(
          labelText: 'Label (optional)',
          hintText: 'For example, tea break',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: _opening ? null : _openClock,
          icon: _opening
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.alarm_add_rounded),
          label: const Text('Open Clock timer'),
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
      if (_notice != null) ...[
        const SizedBox(height: 12),
        Text(
          _notice!,
          style: TextStyle(color: Theme.of(context).colorScheme.primary),
        ),
      ],
    ],
  );
}
