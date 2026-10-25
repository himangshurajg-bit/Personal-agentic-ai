import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

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
