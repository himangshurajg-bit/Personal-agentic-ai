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
