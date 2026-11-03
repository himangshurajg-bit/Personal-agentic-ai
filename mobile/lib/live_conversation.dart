import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:record/record.dart';

import 'assistant_state.dart' show ServiceException;

/// Parses Deepgram's streaming Results events into complete utterances.
/// Intermediate/final segments are kept only in memory until the endpoint event.
class DeepgramLiveTranscriptParser {
  String _pending = '';

  String? addMessage(Object? message) {
    if (message is! String) return null;
    final decoded = jsonDecode(message);
    if (decoded is! Map<String, dynamic>) return null;
    final type = decoded['type'];
    if (type == 'UtteranceEnd') return _takePending();
    if (type != 'Results') return null;

    final channel = decoded['channel'];
    final alternatives = channel is Map ? channel['alternatives'] : null;
    final transcript = alternatives is List && alternatives.isNotEmpty
        ? alternatives.first['transcript']
        : null;
    final text = transcript is String ? transcript.trim() : '';
    final isFinal = decoded['is_final'] == true;
    final speechFinal = decoded['speech_final'] == true;

    if (text.isNotEmpty && isFinal) _append(text);
    if (!speechFinal) return null;
    // Deepgram normally marks speech_final as final too; retain the current
    // segment if a provider event marks only speech_final.
    if (text.isNotEmpty && !isFinal) _append(text);
    return _takePending();
  }

  void reset() => _pending = '';

  void _append(String value) {
    if (_pending.isEmpty) {
      _pending = value;
    } else if (!_pending.endsWith(value)) {
      _pending = '$_pending $value';
    }
  }

  String? _takePending() {
    final completed = _pending.trim();
    _pending = '';
    return completed.isEmpty ? null : completed;
  }
}

/// Low-latency Deepgram WebSocket transcription for an explicitly started
/// live conversation. Audio frames are streamed and not retained by this class.
class DeepgramLiveSession {
  DeepgramLiveSession({
    required this.apiKey,
    required this.locale,
    required this.onUtterance,
    required this.onError,
  });

  final String apiKey;
  final String locale;
  final void Function(String utterance) onUtterance;
  final void Function(String message) onError;
  final DeepgramLiveTranscriptParser _parser = DeepgramLiveTranscriptParser();
  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  bool _closed = false;

  static const supportedLocales = {'en-IN', 'as-IN', 'hi-IN'};

  Future<void> start() async {
    if (!supportedLocales.contains(locale)) {
      throw ServiceException(
        'Live Deepgram transcription supports English, Assamese and Hindi only. No connection was made.',
      );
    }
    if (apiKey.trim().isEmpty) {
      throw ServiceException('Add your Deepgram API key in Settings first.');
    }
    final language = switch (locale) {
      'as-IN' => 'as',
      'hi-IN' => 'hi',
      _ => 'en-IN',
    };
    final uri = Uri.https('api.deepgram.com', '/v1/listen', {
      'model': 'nova-3',
      'language': language,
      'encoding': 'linear16',
      'sample_rate': '16000',
      'channels': '1',
      'interim_results': 'true',
      'smart_format': 'true',
      'endpointing': '300',
      'utterance_end_ms': '1000',
      'vad_events': 'true',
    });
    try {
      final socket = await WebSocket.connect(
        uri.toString(),
        headers: {'Authorization': 'Token ${apiKey.trim()}'},
      ).timeout(const Duration(seconds: 12));
      if (_closed) {
        await socket.close();
        throw ServiceException(
          'Live voice session was stopped before connecting.',
        );
      }
      _socket = socket;
      socket.pingInterval = const Duration(seconds: 20);
      _subscription = socket.listen(
        (event) {
          try {
            final utterance = _parser.addMessage(event);
            if (utterance != null && !_closed) onUtterance(utterance);
          } catch (_) {
            _fail(
              'Deepgram returned an unreadable live transcript. The session stopped.',
            );
          }
        },
        onError: (_) => _fail(
          'Deepgram live transcription lost its connection. The session stopped; no provider fallback was used.',
        ),
        onDone: () {
          if (!_closed) {
            _fail('Deepgram live transcription ended. The session stopped.');
          }
        },
        cancelOnError: true,
      );
    } on ServiceException {
      rethrow;
    } catch (_) {
      _closed = true;
      throw ServiceException(
        'Could not start Deepgram live transcription. Check the key and connection; no other provider was used.',
      );
    }
  }

  void addAudio(Uint8List frame) {
    if (_closed || frame.isEmpty) return;
    try {
      _socket?.add(frame);
    } catch (_) {
      _fail('Audio could not be sent to Deepgram. The live session stopped.');
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final socket = _socket;
    _socket = null;
    final subscription = _subscription;
    _subscription = null;
    try {
      socket?.add(jsonEncode({'type': 'CloseStream'}));
      await subscription?.cancel();
      await socket?.close(WebSocketStatus.normalClosure);
    } catch (_) {
      // Stop is best-effort; never retry or keep streaming after the user's stop.
    }
    _parser.reset();
  }

  void _fail(String message) {
    if (_closed) return;
    _closed = true;
    _parser.reset();
    unawaited(_subscription?.cancel());
    unawaited(_socket?.close(WebSocketStatus.goingAway));
    _subscription = null;
    _socket = null;
    onError(message);
  }
}

class LiveConversationService {
  static const MethodChannel _channel = MethodChannel(
    'personal_assistant/live_conversation',
  );

  static Future<void> start() async {
    try {
      await _channel.invokeMethod<void>('start');
    } on PlatformException catch (error) {
      throw ServiceException(
        error.message ??
            'Android could not start the microphone notification service.',
      );
    } on MissingPluginException {
      throw ServiceException(
        'Background live conversation is unavailable on this Android build.',
      );
    }
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      // The user stop path still closes audio and Deepgram locally.
    } on MissingPluginException {
      // Other Flutter platforms have no Android foreground service.
    }
  }
}

/// User-started local wake gate. Android's on-device recognizer handles this
/// locally; network transcription is started only after the wake phrase.
class WakeWordManager {
  static const MethodChannel _channel = MethodChannel(
    'personal_assistant/voice_tools',
  );
  Future<void> start(String locale) =>
      _channel.invokeMethod<void>('start_wake_word', {'locale': locale});
  Future<void> stop() => _channel.invokeMethod<void>('stop_wake_word');
}

/// Narrow wrapper around the microphone stream used by a live session.
class AudioCaptureManager {
  final AudioRecorder _recorder = AudioRecorder();
  Future<bool> hasPermission() => _recorder.hasPermission();
  Future<Stream<Uint8List>> startPcm16Stream() => startStream(
    const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
    ),
  );
  Future<Stream<Uint8List>> startStream(RecordConfig config) =>
      _recorder.startStream(config);
  Future<void> stop() async {
    await _recorder.stop();
  }

  Future<void> dispose() => _recorder.dispose();
}

/// Interruptible playback facade; UI can stop the current speech without
/// ending the user-started voice session.
class AudioPlaybackManager {
  AudioPlaybackManager(this._stopPlayback);
  final Future<void> Function() _stopPlayback;
  Future<void> interrupt() => _stopPlayback();
}

class VoiceTools {
  static const MethodChannel _channel = MethodChannel(
    'personal_assistant/voice_tools',
  );
  static Future<List<Map<String, dynamic>>> listApps() async =>
      ((await _channel.invokeListMethod<Object?>('list_apps')) ?? const [])
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .toList();
  static Future<Map<String, dynamic>> executeApp(
    String packageName, {
    required bool approved,
  }) async => Map<String, dynamic>.from(
    await _channel.invokeMapMethod<String, dynamic>('execute', {
          'action_id': 'launch_app',
          'package_name': packageName,
          'approved': approved,
        }) ??
        const {},
  );
  static Future<Map<String, dynamic>> searchWeb(
    String query, {
    required bool approved,
  }) async => Map<String, dynamic>.from(
    await _channel.invokeMapMethod<String, dynamic>('execute', {
          'action_id': 'web_search',
          'query': query,
          'approved': approved,
        }) ??
        const {},
  );
  static Future<Map<String, dynamic>> prepareMessage({
    required String recipient,
    required String body,
    required bool approved,
  }) async => Map<String, dynamic>.from(
    await _channel.invokeMapMethod<String, dynamic>('execute', {
          'action_id': 'prepare_message',
          'recipient': recipient,
          'message': body,
          'approved': approved,
        }) ??
        const {},
  );
  static Future<List<Map<String, dynamic>>> readNotifications({
    required bool approved,
  }) async =>
      ((await _channel.invokeListMethod<Object?>('read_notifications', {
                'approved': approved,
              })) ??
              const [])
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .toList();
  static Future<Map<String, dynamic>> permissionStatus() async =>
      Map<String, dynamic>.from(
        await _channel.invokeMapMethod<String, dynamic>(
              'voice_permission_status',
            ) ??
            const {},
      );
  static Future<void> openNotificationAccessSettings() =>
      _channel.invokeMethod<void>('open_notification_access_settings');
}

class SpokenAppLaunch {
  const SpokenAppLaunch(this.name);
  final String name;
  static SpokenAppLaunch? parse(String text) {
    final match = RegExp(
      r'^\s*(?:please\s+)?(?:open|launch|start)\s+(?:the\s+)?(.+?)\s*$',
      caseSensitive: false,
    ).firstMatch(text);
    final name = match?.group(1)?.trim();
    if (name == null || name.isEmpty || name.length > 80) return null;
    return SpokenAppLaunch(name);
  }
}

bool isSpokenNotificationRead(String text) => RegExp(
  r'^\s*(?:please\s+)?(?:read|check)\s+(?:my\s+)?notifications\s*[?.!]*\s*$',
  caseSensitive: false,
).hasMatch(text);

/// A narrowly scoped, explicitly phrased request to turn the device flash off.
/// Android presents its own confirmation and reports whether the state changed.
bool isSpokenTorchOffCommand(String text) => RegExp(
  r'^\s*(?:please\s+)?(?:turn|switch)\s+(?:(?:off)\s+(?:my\s+)?(?:phone\s+)?(?:the\s+)?(?:flashlight|torch)|(?:my\s+)?(?:phone\s+)?(?:the\s+)?(?:flashlight|torch)\s+off)\s*[?.!]*\s*$',
  caseSensitive: false,
).hasMatch(text);

/// Explicit web-search commands are reviewed before Android hands the query
/// to a search app. These do not imply that search results were inspected.
class SpokenWebSearch {
  const SpokenWebSearch(this.query);
  final String query;

  static SpokenWebSearch? parse(String text) {
    final match = RegExp(
      r'^\s*(?:please\s+)?(?:search(?:\s+the\s+web)?\s+for|look\s+up)\s+(.+?)\s*[?.!]*\s*$',
      caseSensitive: false,
    ).firstMatch(text);
    final query = match?.group(1)?.trim();
    if (query == null || query.isEmpty || query.length > 2000) return null;
    return SpokenWebSearch(query);
  }
}

/// Parses only explicit, bounded message-draft commands. Recipient names are
/// not resolved against contacts; Android's messaging app lets the user choose.
class SpokenMessageDraft {
  const SpokenMessageDraft({required this.recipient, required this.body});
  final String recipient;
  final String body;

  static SpokenMessageDraft? parse(String text) {
    final match = RegExp(
      r'^\s*(?:please\s+)?(?:text|message|send\s+(?:a\s+)?(?:text\s+)?message)\s+(?:to\s+)?(.+?)\s*(?:saying|that|:|,)\s*(.+?)\s*[?.!]*\s*$',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(text);
    final recipient = match?.group(1)?.trim();
    final body = match?.group(2)?.trim();
    if (recipient == null ||
        recipient.isEmpty ||
        recipient.length > 80 ||
        body == null ||
        body.isEmpty ||
        body.length > 4000) {
      return null;
    }
    return SpokenMessageDraft(recipient: recipient, body: body);
  }
}
