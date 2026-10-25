import 'package:flutter/services.dart';

/// A finite, user-started chat request shown as an ongoing Android notification.
/// It is intentionally not a background service and does not imply background
/// execution or an Android 16 Live Update.
enum AssistantTaskStatus {
  preparing,
  waitingForReply,
  workingOffline,
  receivingReply,
}

extension AssistantTaskStatusLabel on AssistantTaskStatus {
  String get label => switch (this) {
    AssistantTaskStatus.preparing => 'Preparing your request',
    AssistantTaskStatus.waitingForReply => 'Waiting for the selected AI',
    AssistantTaskStatus.workingOffline => 'Running the on-device model',
    AssistantTaskStatus.receivingReply => 'Receiving the reply',
  };
}

class AssistantTaskSnapshot {
  const AssistantTaskSnapshot({
    required this.id,
    required this.title,
    required this.status,
  });

  final String id;
  final String title;
  final AssistantTaskStatus status;

  AssistantTaskSnapshot copyWith({AssistantTaskStatus? status}) =>
      AssistantTaskSnapshot(
        id: id,
        title: title,
        status: status ?? this.status,
      );
}

abstract interface class AssistantTaskNotificationPort {
  Future<void> show(AssistantTaskSnapshot task);
  Future<void> update(AssistantTaskSnapshot task);
  Future<void> dismiss(String id);
}

class MethodChannelAssistantTaskNotificationPort
    implements AssistantTaskNotificationPort {
  MethodChannelAssistantTaskNotificationPort({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'personal_assistant/task_tracker';
  final MethodChannel _channel;

  @override
  Future<void> show(AssistantTaskSnapshot task) =>
      _quietly(_channel.invokeMethod<void>('show_task', _arguments(task)));

  @override
  Future<void> update(AssistantTaskSnapshot task) =>
      _quietly(_channel.invokeMethod<void>('update_task', _arguments(task)));

  @override
  Future<void> dismiss(String id) =>
      _quietly(_channel.invokeMethod<void>('dismiss_task', {'id': id}));

  Map<String, Object> _arguments(AssistantTaskSnapshot task) => {
    'id': task.id,
    'title': task.title,
    'status': task.status.name,
    'status_label': task.status.label,
  };

  Future<void> _quietly(Future<void> operation) async {
    try {
      await operation;
    } on PlatformException {
      // Notification permission or platform availability never blocks chat.
    } on MissingPluginException {
      // Non-Android and older builds keep chat usable without the notification.
    } catch (_) {
      // Notification failures must never fail the user-requested chat task.
    }
  }
}

/// Tracks one currently-running, user-started chat request. Stale updates from
/// a cancelled request are ignored, so they cannot replace a newer task.
class AssistantTaskTracker {
  AssistantTaskTracker(this._port);

  final AssistantTaskNotificationPort _port;
  AssistantTaskSnapshot? _active;

  AssistantTaskSnapshot? get active => _active;

  Future<void> start({required String id, required String title}) async {
    final cleanTitle = title.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (id.isEmpty || cleanTitle.isEmpty) return;
    final old = _active;
    if (old != null) {
      _active = null;
      await _port.dismiss(old.id);
    }
    final task = AssistantTaskSnapshot(
      id: id,
      title: cleanTitle.length <= 100
          ? cleanTitle
          : '${cleanTitle.substring(0, 97)}…',
      status: AssistantTaskStatus.preparing,
    );
    _active = task;
    await _port.show(task);
  }

  Future<void> update(String id, AssistantTaskStatus status) async {
    final task = _active;
    if (task == null || task.id != id || task.status == status) return;
    final updated = task.copyWith(status: status);
    _active = updated;
    await _port.update(updated);
  }

  Future<void> finish(String id) async {
    if (_active?.id != id) return;
    _active = null;
    await _port.dismiss(id);
  }
}

/// A notification tap only starts one-shot voice input after startup and only
/// when the app is unlocked. Locked/not-ready launches fall back to ordinary
/// chat; they never start a microphone in the background.
String taskVoiceEntryRoute({required bool ready, required bool locked}) =>
    ready && !locked ? '/task-voice' : '/chat';
