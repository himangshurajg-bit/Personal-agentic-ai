import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'assistant_state.dart' show ServiceException;

/// Deepgram is used here for explicit, one-shot speech-to-text only. It is not
/// an LLM. Audio is supplied by a foreground, user-started recorder and is
/// never retained by this adapter.
class DeepgramTranscriber {
  DeepgramTranscriber({http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? http.Client.new;

  final http.Client Function() _clientFactory;
  http.Client? _activeClient;
  int _generation = 0;

  Future<String> transcribe({
    required Uint8List pcm16le,
    required String apiKey,
    required String locale,
  }) async {
    final key = apiKey.trim();
    if (key.isEmpty) {
      throw ServiceException('Add your Deepgram API key in Settings first.');
    }
    if (pcm16le.isEmpty) {
      throw ServiceException('No speech was recorded. Try again.');
    }
    if (!const ['en-IN', 'hi-IN'].contains(locale)) {
      throw ServiceException(
        'Deepgram voice input is currently available for English or Hindi only. Choose one of those languages in Settings.',
      );
    }

    final generation = ++_generation;
    final client = _clientFactory();
    _activeClient = client;
    final language = locale == 'hi-IN' ? 'hi' : 'en';
    final request = http.Request(
      'POST',
      Uri.https('api.deepgram.com', '/v1/listen', {
        'model': 'nova-3',
        'language': language,
        'smart_format': 'true',
        'encoding': 'linear16',
        'sample_rate': '16000',
        'channels': '1',
      }),
    )
      ..followRedirects = false
      ..headers.addAll({
        'Authorization': 'Token $key',
        'Content-Type': 'audio/raw',
      })
      ..bodyBytes = pcm16le;

    try {
      final streamed = await client.send(request);
      final response = await http.Response.fromStream(streamed);
      if (generation != _generation) {
        throw ServiceException('Deepgram transcription was cancelled.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ServiceException(
          response.statusCode == 401 || response.statusCode == 403
              ? 'Deepgram rejected the saved API key. Check it in Settings.'
              : 'Deepgram transcription failed (HTTP ${response.statusCode}). No retry was made.',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw ServiceException('Deepgram returned an unreadable response.');
      }
      final results = decoded['results'];
      final channels = results is Map ? results['channels'] : null;
      final alternatives = channels is List && channels.isNotEmpty
          ? channels.first['alternatives']
          : null;
      final transcript = alternatives is List && alternatives.isNotEmpty
          ? alternatives.first['transcript']
          : null;
      if (transcript is! String || transcript.trim().isEmpty) {
        throw ServiceException('No speech was recognized. Try again or type.');
      }
      return transcript.trim();
    } on ServiceException {
      rethrow;
    } catch (_) {
      if (generation != _generation) {
        throw ServiceException('Deepgram transcription was cancelled.');
      }
      throw ServiceException(
        'Could not reach Deepgram. Check your connection and try again.',
      );
    } finally {
      if (identical(_activeClient, client)) _activeClient = null;
      client.close();
    }
  }

  void cancel() {
    _generation++;
    _activeClient?.close();
    _activeClient = null;
  }
}
