import 'dart:convert';

import 'package:http/http.dart' as http;

import 'assistant_state.dart' show ServiceException, checkedEndpoint;

/// Selectable protocol adapters, not a claim that a model is installed.
class EngineConfig {
  final String mode, origin, model, token;
  const EngineConfig({
    required this.mode,
    required this.origin,
    required this.model,
    required this.token,
  });
  String get description => switch (mode) {
    'offline' => 'Offline · Gemma experimental',
    'gemini' => 'Online · Gemini 2.5 Flash',
    'compatible' => 'Online · OpenAI-compatible',
    _ => 'Online · private FastAPI service',
  };
  http.Request request(String conversation, String prompt) {
    if (mode == 'offline') {
      throw ServiceException(
        'Offline chat must use the explicitly opted-in local Gemma runtime. No online fallback was made.',
      );
    }
    if (token.isEmpty) {
      throw ServiceException(
        'Configure this provider in Settings first. No data was sent.',
      );
    }
    final base = mode == 'gemini' ? Uri.parse(origin) : checkedEndpoint(origin);
    if (mode == 'gemini' && base.scheme != 'https') {
      throw ServiceException('Gemini API requires HTTPS.');
    }
    if (mode == 'compatible' && base.scheme != 'https') {
      throw ServiceException('Online providers require HTTPS.');
    }
    if (mode == 'compatible' && model.trim().isEmpty) {
      throw ServiceException('Enter the provider model identifier.');
    }
    if (!['private_service', 'compatible', 'gemini'].contains(mode)) {
      throw ServiceException('Unsupported AI engine.');
    }
    if (mode == 'private_service' && prompt.length > 8000) {
      throw ServiceException(
        'Selected prompt/history/memories exceed the private service 8000-character request limit. Shorten or deselect optional context; nothing was sent.',
      );
    }
    final req = http.Request(
      'POST',
      mode == 'gemini'
          ? Uri.parse('$origin:generateContent')
          : base.resolve(
              mode == 'compatible' ? '/v1/chat/completions' : '/chat',
            ),
    )..followRedirects = false;
    req.headers['Content-Type'] = 'application/json';
    if (mode == 'gemini') {
      req.headers['x-goog-api-key'] = token;
      req.body = jsonEncode({
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': prompt},
            ],
          },
        ],
      });
    } else {
      req.headers['Authorization'] = 'Bearer $token';
      req.body = jsonEncode(
        mode == 'compatible'
            ? {
                'model': model,
                'stream': true,
                'messages': [
                  {'role': 'user', 'content': prompt},
                ],
              }
            : {'conversation': conversation, 'text': prompt},
      );
    }
    return req;
  }

  Stream<Map<String, dynamic>> events(Stream<List<int>> bytes) async* {
    if (mode == 'gemini') {
      final body = await bytes.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw ServiceException('Gemini returned an unexpected response.');
      }
      if (decoded['error'] != null) {
        throw ServiceException(
          'Gemini could not complete this request. Check model access and quota; nothing was retried.',
        );
      }
      final candidates = decoded['candidates'];
      final candidate =
          candidates is List && candidates.isNotEmpty && candidates.first is Map
          ? candidates.first as Map
          : null;
      final content = candidate == null ? null : candidate['content'];
      final parts = content is Map ? content['parts'] : null;
      final text = parts is List
          ? parts
                .whereType<Map>()
                .map((part) => part['text'])
                .whereType<String>()
                .join()
          : '';
      if (text.isEmpty) {
        throw ServiceException(
          'Gemini returned no text. The response may have been blocked or incomplete; nothing was retried.',
        );
      }
      yield {'type': 'delta', 'text': text};
      yield {'type': 'done'};
      return;
    }
    await for (final line
        in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
      if (mode == 'private_service') {
        if (line.trim().isNotEmpty) {
          yield Map<String, dynamic>.from(jsonDecode(line));
        }
      } else {
        if (!line.startsWith('data:')) continue;
        final value = line.substring(5).trim();
        if (value == '[DONE]') {
          yield {'type': 'done'};
          continue;
        }
        final event = jsonDecode(value) as Map;
        if (event['error'] != null) {
          throw ServiceException(
            'Provider reported an error. Nothing was retried.',
          );
        }
        final choices = event['choices'] as List? ?? [];
        if (choices.isEmpty) continue;
        final content = choices.first['delta']?['content'];
        if (content is String && content.isNotEmpty) {
          yield {'type': 'delta', 'text': content};
        }
        // A normal stop is completion; length/tool-call stops are not complete answers.
        final reason = choices.first['finish_reason'];
        if (reason == 'stop') yield {'type': 'done'};
        if (reason != null && reason != 'stop') {
          throw ServiceException(
            'Provider stopped with $reason; response is incomplete.',
          );
        }
      }
    }
  }
}
