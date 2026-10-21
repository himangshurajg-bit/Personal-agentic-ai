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
  String get description => mode == 'offline'
      ? 'Offline · model not installed'
      : mode == 'compatible'
      ? 'Online · OpenAI-compatible'
      : 'Online · private FastAPI service';
  http.Request request(String conversation, String prompt) {
    if (mode == 'offline') {
      throw ServiceException(
        'Offline AI is not installed. Model selection needs phone RAM/storage and language testing. No online fallback was made.',
      );
    }
    if (token.isEmpty) {
      throw ServiceException(
        'Configure this provider in Settings first. No data was sent.',
      );
    }
    final base = checkedEndpoint(origin);
    if (mode == 'compatible' && base.scheme != 'https') {
      throw ServiceException('Online providers require HTTPS.');
    }
    if (mode == 'compatible' && model.trim().isEmpty) {
      throw ServiceException('Enter the provider model identifier.');
    }
    if (!['private_service', 'compatible'].contains(mode)) {
      throw ServiceException('Unsupported AI engine.');
    }
    if (mode == 'private_service' && prompt.length > 8000) {
      throw ServiceException(
        'Selected prompt/history/memories exceed the private service 8000-character request limit. Shorten or deselect optional context; nothing was sent.',
      );
    }
    final req = http.Request(
      'POST',
      base.resolve(mode == 'compatible' ? '/v1/chat/completions' : '/chat'),
    )..followRedirects = false;
    req.headers.addAll({
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    });
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
    return req;
  }

  Stream<Map<String, dynamic>> events(Stream<List<int>> bytes) async* {
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
