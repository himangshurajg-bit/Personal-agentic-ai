import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/assistant_task_tracker.dart';

class _FakeNotifications implements AssistantTaskNotificationPort {
  final shown = <AssistantTaskSnapshot>[];
  final updated = <AssistantTaskSnapshot>[];
  final dismissed = <String>[];

  @override
  Future<void> show(AssistantTaskSnapshot task) async => shown.add(task);

  @override
  Future<void> update(AssistantTaskSnapshot task) async => updated.add(task);

  @override
  Future<void> dismiss(String id) async => dismissed.add(id);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AssistantTaskTracker', () {
    test(
      'tracks a finite task through status changes and completion',
      () async {
        final port = _FakeNotifications();
        final tracker = AssistantTaskTracker(port);

        await tracker.start(id: 'chat-1', title: '  explain   this topic  ');
        expect(tracker.active?.title, 'explain this topic');
        expect(tracker.active?.status, AssistantTaskStatus.preparing);
        expect(port.shown, hasLength(1));

        await tracker.update('chat-1', AssistantTaskStatus.waitingForReply);
        await tracker.update('chat-1', AssistantTaskStatus.receivingReply);
        expect(port.updated.map((task) => task.status), [
          AssistantTaskStatus.waitingForReply,
          AssistantTaskStatus.receivingReply,
        ]);

        await tracker.finish('chat-1');
        expect(tracker.active, isNull);
        expect(port.dismissed, ['chat-1']);
      },
    );

    test('stale callbacks cannot update or dismiss a newer task', () async {
      final port = _FakeNotifications();
      final tracker = AssistantTaskTracker(port);
      await tracker.start(id: 'chat-old', title: 'old task');
      await tracker.start(id: 'chat-new', title: 'new task');

      await tracker.update('chat-old', AssistantTaskStatus.receivingReply);
      await tracker.finish('chat-old');

      expect(tracker.active?.id, 'chat-new');
      expect(port.dismissed, ['chat-old']);
      expect(port.updated, isEmpty);
    });

    test('limits notification title and ignores empty task data', () async {
      final port = _FakeNotifications();
      final tracker = AssistantTaskTracker(port);
      await tracker.start(id: '', title: 'not started');
      await tracker.start(id: 'chat-1', title: 'x' * 101);

      expect(port.shown, hasLength(1));
      expect(port.shown.single.title.length, 98);
      expect(port.shown.single.title.endsWith('…'), isTrue);
    });

    test(
      'missing Android notification bridge does not fail chat lifecycle',
      () async {
        const channel = MethodChannel('test/missing_task_notification_bridge');
        final tracker = AssistantTaskTracker(
          MethodChannelAssistantTaskNotificationPort(channel: channel),
        );

        await tracker.start(id: 'chat-1', title: 'test request');
        await tracker.update('chat-1', AssistantTaskStatus.workingOffline);
        await tracker.finish('chat-1');
        expect(tracker.active, isNull);
      },
    );
  });

  group('notification voice entry', () {
    test('only starts one-shot entry after readiness and unlock', () {
      expect(taskVoiceEntryRoute(ready: false, locked: false), '/chat');
      expect(taskVoiceEntryRoute(ready: true, locked: true), '/chat');
      expect(taskVoiceEntryRoute(ready: true, locked: false), '/task-voice');
    });
  });
}
