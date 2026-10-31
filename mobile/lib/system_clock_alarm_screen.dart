import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'assistant_state.dart';

/// Opens Android Clock with a reviewed one-off alarm time; the user confirms it there.
class SystemClockAlarmScreen extends StatefulWidget {
  const SystemClockAlarmScreen({super.key});

  @override
  State<SystemClockAlarmScreen> createState() => _SystemClockAlarmScreenState();
}

class _SystemClockAlarmScreenState extends State<SystemClockAlarmScreen> {
  TimeOfDay? _time;
  String? _error;
  String? _notice;
  bool _opening = false;

  String _format(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  Future<void> _chooseAndOpen() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _time ?? TimeOfDay.now(),
      helpText: 'Choose alarm time',
    );
    if (selected == null || !mounted) return;
    setState(() {
      _time = selected;
      _error = null;
      _notice = null;
    });
    final formatted = _format(selected);
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Review alarm'),
        content: Text(
          'Open Android Clock with a one-off alarm at $formatted? You must confirm and save it in Clock.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Open Clock'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() {
      _opening = true;
      _error = null;
      _notice = null;
    });
    try {
      await AssistantState.device.invokeMethod<void>('set_system_alarm', {
        'hour': selected.hour,
        'minute': selected.minute,
      });
      if (mounted) {
        setState(
          () => _notice =
              'Clock opened at $formatted. Confirm and save the alarm there; Personal AI cannot verify it.',
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
      Text('System Clock alarm', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      const Text(
        'Choose a time, review it, then open Android Clock. The alarm is not saved until you confirm it in Clock.',
      ),
      const SizedBox(height: 18),
      if (_time != null)
        Text(
          'Selected time: ${_format(_time!)}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: _opening ? null : _chooseAndOpen,
          icon: _opening
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.alarm_rounded),
          label: const Text('Choose and review alarm'),
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
