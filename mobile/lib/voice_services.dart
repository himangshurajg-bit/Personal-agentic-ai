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
    final request =
        http.Request(
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

/// Optional Gemini 3.8 Flash-Lite expressive speech from the exact assistant
/// reply text. The user supplies the existing Gemini API key from secure
/// storage; this adapter never stores it or makes a provider call on its own.
class GeminiExpressiveSpeechSynthesizer {
  GeminiExpressiveSpeechSynthesizer({http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? http.Client.new;

  final http.Client Function() _clientFactory;
  static const endpoint =
      'https://generativelanguage.googleapis.com/v1beta/interactions';
  static const model = 'gemini-3.8-flash-lite-tts';
  static const supportedLocales = {'en-IN', 'as-IN', 'hi-IN'};
  static const expressionStyles = {
    'natural': 'Speak naturally, like a warm, expressive human conversational partner. Match the emotion clearly expressed by the exact words, including a firm or frustrated tone when appropriate and light laughter only when the text genuinely calls for it. Keep the transcript verbatim; do not add words or sound effects.',
    'cheerful': 'Speak cheerfully and warmly, with lively but natural conversational energy. Keep the transcript verbatim; do not add words or sound effects.',
    'curious': 'Speak with genuine curiosity and interest, using natural conversational emphasis. Keep the transcript verbatim; do not add words or sound effects.',
    'calm': 'Speak calmly and reassuringly, with a gentle human conversational pace. Keep the transcript verbatim; do not add words or sound effects.',
    'serious': 'Speak seriously and clearly, with measured emphasis. Keep the transcript verbatim; do not add words or sound effects.',
    'angry': 'Speak with controlled anger and firm intensity, without shouting unless the words clearly warrant it. Keep the transcript verbatim; do not add words or sound effects.',
    'laughing': 'Speak with genuine amusement and light laughter where natural. Keep the transcript verbatim; do not add words or sound effects.',
  };
  static String styleFor(String expression) =>
      expressionStyles[expression] ?? expressionStyles['natural']!;

  Future<Uint8List> synthesize({
    required String text,
    required String apiKey,
    required String locale,
    String style = 'Speak naturally, like a warm, expressive human conversational partner. Match the emotion clearly expressed by the exact words, including a firm or frustrated tone when appropriate and light laughter only when the text genuinely calls for it. Keep the transcript verbatim; do not add words or sound effects.',
  }) async {
    final key = apiKey.trim();
    final transcript = text.trim();
    if (key.isEmpty) {
      throw ServiceException('Add a Gemini API key in Settings first.');
    }
    if (!supportedLocales.contains(locale)) {
      throw ServiceException(
        'Gemini expressive speech is enabled for English, Assamese and Hindi only. No request was made.',
      );
    }
    if (transcript.isEmpty || transcript.runes.length > 5000) {
      throw ServiceException('Voice text must contain 1–5,000 characters.');
    }
    if (style.trim().isEmpty || style.runes.length > 500) {
      throw ServiceException('Choose a valid speech style.');
    }

    final client = _clientFactory();
    try {
      final request = http.Request('POST', Uri.parse(endpoint))
        ..followRedirects = false
        ..headers.addAll({
          'x-goog-api-key': key,
          'Content-Type': 'application/json',
        })
        ..body = jsonEncode({
          'model': model,
          'input': [
            {
              'type': 'text',
              'text': transcript,
              'annotations': [
                {'type': 'speech_metadata', 'style': style.trim()},
              ],
            },
          ],
          'response_format': {'type': 'audio', 'mime_type': 'audio/wav'},
          'generation_config': {
            'speech_config': [
              {'voice': 'Kore'},
            ],
          },
        });
      final response = await http.Response.fromStream(
        await client.send(request).timeout(const Duration(seconds: 30)),
      ).timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ServiceException(
          response.statusCode == 401 || response.statusCode == 403
              ? 'Google Gemini rejected the saved API key or access. Check the Gemini key in Settings.'
              : response.statusCode == 429
              ? 'Google Gemini TTS reached a quota or rate limit. No other cloud voice was used.'
              : 'Google Gemini TTS failed (HTTP ${response.statusCode}). No other cloud voice was used.',
        );
      }
      final decoded = jsonDecode(response.body);
      final bytes = _extractAudio(decoded);
      if (bytes == null || bytes.length < 44 || bytes.length > 12_000_000) {
        throw ServiceException(
          'Google Gemini returned missing, invalid or oversized speech audio.',
        );
      }
      if (String.fromCharCodes(bytes.take(4)) != 'RIFF' ||
          String.fromCharCodes(bytes.skip(8).take(4)) != 'WAVE') {
        throw ServiceException('Google Gemini returned an invalid WAV file.');
      }
      return bytes;
    } on ServiceException {
      rethrow;
    } catch (_) {
      throw ServiceException(
        'Could not reach Google Gemini TTS. Check the connection; no other cloud voice was used.',
      );
    } finally {
      client.close();
    }
  }

  static Uint8List? _extractAudio(Object? decoded) {
    if (decoded is! Map<String, dynamic>) return null;
    final steps = decoded['steps'];
    if (steps is! List) return null;
    for (final step in steps) {
      if (step is! Map) continue;
      final content = step['content'];
      if (content is! List) continue;
      for (final part in content) {
        if (part is! Map || part['type'] != 'audio') continue;
        final data = part['data'];
        if (data is! String || data.isEmpty) continue;
        try {
          return Uint8List.fromList(base64Decode(data));
        } on FormatException {
          throw ServiceException(
            'Google Gemini returned unreadable speech audio.',
          );
        }
      }
    }
    return null;
  }
}

/// Direct, opt-in Azure Speech text-to-speech. The API key is supplied by the
/// caller from secure storage and is never included in errors or response text.
class AzureSpeechSynthesizer {
  AzureSpeechSynthesizer({http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? http.Client.new;

  final http.Client Function() _clientFactory;
  static const supportedLocales = {'en-IN', 'hi-IN'};
  static const voices = {
    'en-IN': 'en-IN-NeerjaNeural',
    'hi-IN': 'hi-IN-SwaraNeural',
  };
  static final _regionPattern = RegExp(r'^[a-z0-9-]{2,50}$');

  Future<Uint8List> synthesize({
    required String text,
    required String apiKey,
    required String region,
    required String locale,
    required double rate,
  }) async {
    final key = apiKey.trim();
    final normalizedRegion = region.trim().toLowerCase();
    if (key.isEmpty) {
      throw ServiceException('Add an Azure Speech key in Settings first.');
    }
    if (!_regionPattern.hasMatch(normalizedRegion)) {
      throw ServiceException(
        'Enter the Azure Speech resource region from Azure.',
      );
    }
    if (!supportedLocales.contains(locale)) {
      throw ServiceException(
        'Azure online voice is available only for English (India) and Hindi. No online request was made.',
      );
    }
    if (text.trim().isEmpty || text.runes.length > 5000) {
      throw ServiceException('Voice text must contain 1–5,000 characters.');
    }
    if (!rate.isFinite || rate < 0.25 || rate > 0.75) {
      throw ServiceException('Speech rate must be between 0.25 and 0.75.');
    }
    final voice = voices[locale]!;
    final ratePercent = (50 + rate * 100).round();
    final ssml =
        '<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="$locale">'
        '<voice name="$voice"><prosody rate="$ratePercent%">${_escapeXml(text)}</prosody></voice>'
        '</speak>';
    final uri = Uri.https(
      '$normalizedRegion.tts.speech.microsoft.com',
      '/cognitiveservices/v1',
    );
    final client = _clientFactory();
    try {
      final request = http.Request('POST', uri)
        ..followRedirects = false
        ..headers.addAll({
          'Ocp-Apim-Subscription-Key': key,
          'Content-Type': 'application/ssml+xml',
          'X-Microsoft-OutputFormat': 'audio-24khz-48kbitrate-mono-mp3',
          'User-Agent': 'PersonalAgenticAI',
        })
        ..body = ssml;
      final response = await http.Response.fromStream(
        await client.send(request).timeout(const Duration(seconds: 30)),
      ).timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ServiceException(
          response.statusCode == 401 || response.statusCode == 403
              ? 'Azure Speech rejected the key or resource access. Check the saved key and region.'
              : response.statusCode == 429
              ? 'Azure Speech rejected the request; its quota or rate limit may have been reached. No paid provider fallback was used.'
              : 'Azure Speech failed (HTTP ${response.statusCode}). No paid provider fallback was used.',
        );
      }
      if (response.bodyBytes.isEmpty ||
          response.bodyBytes.length > 12_000_000) {
        throw ServiceException(
          'Azure Speech returned empty or oversized audio.',
        );
      }
      return Uint8List.fromList(response.bodyBytes);
    } on ServiceException {
      rethrow;
    } catch (_) {
      throw ServiceException(
        'Could not reach Azure Speech. Check the connection and resource region; no other online provider was used.',
      );
    } finally {
      client.close();
    }
  }

  static String _escapeXml(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
