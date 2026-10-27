enum FocusPhase { focus, breakTime }

/// Persisted wall-clock state for the local, foreground-only focus timer.
class FocusTimerSnapshot {
  static const focusSeconds = 25 * 60;
  static const breakSeconds = 5 * 60;

  final FocusPhase phase;
  final int remainingSeconds;
  final DateTime? deadlineUtc;
  final FocusPhase? completedPhase;

  const FocusTimerSnapshot({
    required this.phase,
    required this.remainingSeconds,
    required this.deadlineUtc,
    this.completedPhase,
  });

  bool get isRunning => deadlineUtc != null;

  static int durationFor(FocusPhase phase) =>
      phase == FocusPhase.focus ? focusSeconds : breakSeconds;

  static FocusPhase _next(FocusPhase phase) =>
      phase == FocusPhase.focus ? FocusPhase.breakTime : FocusPhase.focus;

  static FocusPhase? _parsePhase(Object? value) => switch (value) {
    'focus' => FocusPhase.focus,
    'break' => FocusPhase.breakTime,
    _ => null,
  };

  static FocusTimerSnapshot initial() => const FocusTimerSnapshot(
    phase: FocusPhase.focus,
    remainingSeconds: focusSeconds,
    deadlineUtc: null,
  );

  /// Restores safely. An elapsed run advances to the other phase, but never
  /// starts that phase automatically or schedules a notification.
  factory FocusTimerSnapshot.restore(Object? raw, {DateTime? now}) {
    if (raw is! Map) return FocusTimerSnapshot.initial();
    final phase = _parsePhase(raw['phase']);
    final completed = _parsePhase(raw['completed_phase']);
    final fallback = FocusTimerSnapshot.initial();
    if (phase == null) return fallback;
    final duration = durationFor(phase);
    final storedRemaining = raw['remaining_seconds'];
    final remaining =
        storedRemaining is int &&
            storedRemaining >= 1 &&
            storedRemaining <= duration
        ? storedRemaining
        : duration;
    final deadlineText = raw['deadline_utc'];
    final deadline = deadlineText is String
        ? DateTime.tryParse(deadlineText)?.toUtc()
        : null;
    if (deadline == null) {
      return FocusTimerSnapshot(
        phase: phase,
        remainingSeconds: remaining,
        deadlineUtc: null,
        completedPhase: completed,
      );
    }
    final current = now ?? DateTime.now().toUtc();
    final active = FocusTimerSnapshot(
      phase: phase,
      remainingSeconds: remaining,
      deadlineUtc: deadline,
      completedPhase: completed,
    );
    return active.remainingAt(current) == 0 ? active.finish() : active;
  }

  int remainingAt(DateTime now) {
    final deadline = deadlineUtc;
    if (deadline == null) return remainingSeconds;
    final milliseconds = deadline.difference(now.toUtc()).inMilliseconds;
    if (milliseconds <= 0) return 0;
    final seconds = (milliseconds + 999) ~/ 1000;
    return seconds.clamp(0, durationFor(phase)).toInt();
  }

  FocusTimerSnapshot start(DateTime now) {
    if (isRunning) return this;
    final seconds = remainingSeconds.clamp(1, durationFor(phase)).toInt();
    return FocusTimerSnapshot(
      phase: phase,
      remainingSeconds: seconds,
      deadlineUtc: now.toUtc().add(Duration(seconds: seconds)),
    );
  }

  FocusTimerSnapshot pause(DateTime now) {
    if (!isRunning) return this;
    final seconds = remainingAt(now);
    if (seconds == 0) return finish();
    return FocusTimerSnapshot(
      phase: phase,
      remainingSeconds: seconds,
      deadlineUtc: null,
      completedPhase: completedPhase,
    );
  }

  FocusTimerSnapshot select(FocusPhase next) {
    if (isRunning) throw StateError('Pause the timer before changing phase.');
    return FocusTimerSnapshot(
      phase: next,
      remainingSeconds: durationFor(next),
      deadlineUtc: null,
    );
  }

  FocusTimerSnapshot reset() => FocusTimerSnapshot(
    phase: phase,
    remainingSeconds: durationFor(phase),
    deadlineUtc: null,
  );

  /// Stops on completion and prepares the next phase without auto-starting it.
  FocusTimerSnapshot finish() => FocusTimerSnapshot(
    phase: _next(phase),
    remainingSeconds: durationFor(_next(phase)),
    deadlineUtc: null,
    completedPhase: phase,
  );

  FocusTimerSnapshot advance(DateTime now) =>
      isRunning && remainingAt(now) == 0 ? finish() : this;

  Map<String, Object?> toJson() => {
    'phase': phase == FocusPhase.focus ? 'focus' : 'break',
    'remaining_seconds': remainingSeconds,
    'deadline_utc': deadlineUtc?.toUtc().toIso8601String(),
    'completed_phase': switch (completedPhase) {
      FocusPhase.focus => 'focus',
      FocusPhase.breakTime => 'break',
      null => null,
    },
  };
}
