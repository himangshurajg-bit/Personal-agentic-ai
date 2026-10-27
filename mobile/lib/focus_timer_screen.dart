import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'assistant_state.dart';
import 'focus_timer.dart';

class FocusTimerScreen extends StatefulWidget {
  final AssistantState state;
  const FocusTimerScreen({super.key, required this.state});

  @override
  State<FocusTimerScreen> createState() => _FocusTimerScreenState();
}

class _FocusTimerScreenState extends State<FocusTimerScreen>
    with WidgetsBindingObserver {
  late FocusTimerSnapshot _timer;
  late final Timer _ticker;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final stored = widget.state.local.snapshot['focus_timer'];
    _timer = FocusTimerSnapshot.restore(stored);
    if (stored is Map && jsonEncode(stored) != jsonEncode(_timer.toJson())) {
      _persist(_timer);
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _tick();
  }

  void _tick() {
    if (!mounted || !_timer.isRunning) return;
    final next = _timer.advance(DateTime.now().toUtc());
    if (!identical(next, _timer)) {
      setState(() => _timer = next);
      _persist(next);
    } else {
      setState(() {});
    }
  }

  Future<void> _persist(FocusTimerSnapshot next) async {
    try {
      await widget.state.local.change((data) {
        data['focus_timer'] = next.toJson();
      });
      if (mounted) setState(() => _error = null);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not save the timer on this device.');
      }
    }
  }

  Future<void> _change(FocusTimerSnapshot Function(DateTime now) update) async {
    if (_saving) return;
    final next = update(DateTime.now().toUtc());
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.state.local.change((data) {
        data['focus_timer'] = next.toJson();
      });
      if (mounted) setState(() => _timer = next);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not save the timer on this device.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _startPause() => _change((now) {
    if (!_timer.isRunning) return _timer.start(now);
    final current = _timer.advance(now);
    return current.isRunning ? current.pause(now) : current;
  });

  Future<void> _select(FocusPhase phase) async {
    if (_timer.isRunning || _saving || phase == _timer.phase) return;
    await _change((_) => _timer.select(phase));
  }

  static String _clock(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final remainder = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$remainder';
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _timer.remainingAt(DateTime.now().toUtc());
    final duration = FocusTimerSnapshot.durationFor(_timer.phase);
    final completed = _timer.completedPhase;
    final colorScheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(
                  Icons.timer_outlined,
                  size: 34,
                  color: colorScheme.primary,
                ),
                const SizedBox(height: 8),
                Text(
                  'Focus timer',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'A 25-minute focus session and a 5-minute break.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                SizedBox.square(
                  dimension: 194,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: (remaining / duration).clamp(0.0, 1.0),
                          strokeWidth: 10,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _timer.phase == FocusPhase.focus
                                ? 'FOCUS'
                                : 'BREAK',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          Text(
                            _clock(remaining),
                            style: Theme.of(context).textTheme.displaySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SegmentedButton<FocusPhase>(
                  segments: const [
                    ButtonSegment(
                      value: FocusPhase.focus,
                      label: Text('Focus · 25 min'),
                    ),
                    ButtonSegment(
                      value: FocusPhase.breakTime,
                      label: Text('Break · 5 min'),
                    ),
                  ],
                  selected: {_timer.phase},
                  onSelectionChanged: _timer.isRunning || _saving
                      ? null
                      : (selection) => _select(selection.first),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: _saving ? null : _startPause,
                      icon: Icon(
                        _timer.isRunning
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      label: Text(_timer.isRunning ? 'Pause' : 'Start'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () => _change((_) => _timer.reset()),
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: const Text('Reset'),
                    ),
                  ],
                ),
                if (_saving) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                if (completed != null && !_timer.isRunning) ...[
                  const SizedBox(height: 14),
                  Text(
                    '${completed == FocusPhase.focus ? 'Focus' : 'Break'} complete. The next phase is ready when you are.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'The saved deadline keeps the countdown accurate when you return. It does not run a background service or sound an alarm; the timer stays on this device.',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
