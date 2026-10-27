import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/focus_timer.dart';
import 'package:personal_assistant/phone_data.dart';

void main() {
  final start = DateTime.utc(2026, 10, 27, 4, 0);

  test('focus and break countdowns use explicit saved deadlines', () {
    final initial = FocusTimerSnapshot.initial();
    expect(initial.phase, FocusPhase.focus);
    expect(initial.remainingSeconds, 25 * 60);

    final running = initial.start(start);
    expect(running.isRunning, isTrue);
    expect(running.deadlineUtc, start.add(const Duration(minutes: 25)));
    expect(
      running.remainingAt(start.add(const Duration(seconds: 1))),
      24 * 60 + 59,
    );
    expect(running.remainingAt(start.add(const Duration(minutes: 25))), 0);
  });

  test('pause and resume preserve the remaining countdown', () {
    final running = FocusTimerSnapshot.initial().start(start);
    final paused = running.pause(start.add(const Duration(minutes: 3)));
    expect(paused.isRunning, isFalse);
    expect(paused.remainingSeconds, 22 * 60);

    final resumed = paused.start(start.add(const Duration(minutes: 8)));
    expect(resumed.remainingSeconds, 22 * 60);
    expect(resumed.deadlineUtc, start.add(const Duration(minutes: 30)));
  });

  test('phase changes reset duration and completion prepares, but does not start, the next phase', () {
    final breakTimer = FocusTimerSnapshot.initial().select(
      FocusPhase.breakTime,
    );
    expect(breakTimer.remainingSeconds, 5 * 60);
    final completed = FocusTimerSnapshot.initial()
        .start(start)
        .advance(start.add(const Duration(minutes: 25)));
    expect(completed.phase, FocusPhase.breakTime);
    expect(completed.remainingSeconds, 5 * 60);
    expect(completed.completedPhase, FocusPhase.focus);
    expect(completed.isRunning, isFalse);
  });

  test('restore resumes an unexpired deadline and advances an elapsed one', () {
    final running = FocusTimerSnapshot.initial().start(start);
    final restored = FocusTimerSnapshot.restore(
      running.toJson(),
      now: start.add(const Duration(minutes: 4)),
    );
    expect(restored.isRunning, isTrue);
    expect(
      restored.remainingAt(start.add(const Duration(minutes: 4))),
      21 * 60,
    );

    final expired = FocusTimerSnapshot.restore(
      running.toJson(),
      now: start.add(const Duration(minutes: 26)),
    );
    expect(expired.phase, FocusPhase.breakTime);
    expect(expired.remainingSeconds, 5 * 60);
    expect(expired.isRunning, isFalse);
    expect(expired.completedPhase, FocusPhase.focus);
  });

  test('invalid saved values fail closed to a bounded idle timer', () {
    final restored = FocusTimerSnapshot.restore({
      'phase': 'unknown',
      'remaining_seconds': 900000,
      'deadline_utc': 'not a date',
    });
    expect(restored.phase, FocusPhase.focus);
    expect(restored.remainingSeconds, 25 * 60);
    expect(restored.isRunning, isFalse);
  });

  test(
    'local store migrates older records and preserves timer data on reload',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'phone_data_v1':
            '{"chats":{},"memories":[],"tasks":[],"attempts":[],"actions":[]}',
      });
      final storage = const FlutterSecureStorage();
      final data = PhoneData(storage);
      await data.load();
      expect(data.snapshot['focus_timer'], isNull);

      final timer = FocusTimerSnapshot.initial().start(start);
      await data.change((store) => store['focus_timer'] = timer.toJson());
      final restored = PhoneData(storage);
      await restored.load();
      expect(
        FocusTimerSnapshot.restore(
          restored.snapshot['focus_timer'],
          now: start,
        ).deadlineUtc,
        timer.deadlineUtc,
      );
      expect(restored.snapshot['tasks'], isEmpty);
      expect(restored.snapshot['chats'], isEmpty);
    },
  );
}
