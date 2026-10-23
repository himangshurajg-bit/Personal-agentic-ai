import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Named provider endpoints. Credentials are persisted only in secure storage.
class AIProviderProfile {
  final String id;
  final String name;
  final String origin;
  final String model;
  final String apiKey;

  const AIProviderProfile({
    required this.id,
    required this.name,
    required this.origin,
    required this.model,
    required this.apiKey,
  });

  bool get isConfigured =>
      origin.trim().isNotEmpty && model.trim().isNotEmpty && apiKey.isNotEmpty;

  AIProviderProfile copyWith({String? origin, String? model, String? apiKey}) =>
      AIProviderProfile(
        id: id,
        name: name,
        origin: origin ?? this.origin,
        model: model ?? this.model,
        apiKey: apiKey ?? this.apiKey,
      );

  Map<String, String> toSecureMap() => {
    'id': id,
    'origin': origin,
    'model': model,
    'api_key': apiKey,
  };

  static List<AIProviderProfile> defaults() => const [
    AIProviderProfile(
      id: 'gemini',
      name: 'Google Gemini API',
      origin: 'https://generativelanguage.googleapis.com/v1beta',
      model: '',
      apiKey: '',
    ),
    AIProviderProfile(
      id: 'openai',
      name: 'OpenAI API (not ChatGPT plan)',
      origin: 'https://api.openai.com/v1',
      model: '',
      apiKey: '',
    ),
    AIProviderProfile(
      id: 'groq',
      name: 'Groq',
      origin: 'https://api.groq.com/openai/v1',
      model: '',
      apiKey: '',
    ),
    AIProviderProfile(
      id: 'openrouter',
      name: 'OpenRouter',
      origin: 'https://openrouter.ai/api/v1',
      model: '',
      apiKey: '',
    ),
  ];

  static List<AIProviderProfile> fromSecureJson(String? raw) {
    final defaultsById = {for (final p in defaults()) p.id: p};
    if (raw == null || raw.isEmpty) return defaults();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return defaults();
      for (final item in decoded) {
        if (item is! Map) continue;
        final id = item['id'];
        final base = defaultsById[id];
        if (base == null) continue;
        defaultsById[id] = base.copyWith(
          origin: item['origin'] is String
              ? item['origin'] as String
              : base.origin,
          model: item['model'] is String ? item['model'] as String : base.model,
          apiKey: item['api_key'] is String ? item['api_key'] as String : '',
        );
      }
      return [for (final profile in defaults()) defaultsById[profile.id]!];
    } catch (_) {
      return defaults();
    }
  }

  http.Request request(String prompt) {
    if (!isConfigured) {
      throw const ProviderCompareException(
        'Configure this provider first. No request was sent.',
      );
    }
    final parsed = Uri.tryParse(origin.trim());
    if (parsed == null ||
        parsed.scheme != 'https' ||
        !parsed.hasAuthority ||
        parsed.userInfo.isNotEmpty ||
        parsed.hasQuery ||
        parsed.hasFragment) {
      throw const ProviderCompareException(
        'Provider endpoints must use HTTPS and cannot contain embedded credentials.',
      );
    }
    final base = parsed.replace(
      path: parsed.path.endsWith('/') ? parsed.path : '${parsed.path}/',
    );
    final isGemini = id == 'gemini';
    final uri = isGemini
        ? base.resolve(
            'models/${Uri.encodeComponent(model.trim())}:generateContent',
          )
        : base.resolve('chat/completions');
    final req = http.Request('POST', uri)
      ..followRedirects = false
      ..headers['Content-Type'] = 'application/json';
    if (isGemini) {
      req.headers['x-goog-api-key'] = apiKey;
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
      req.headers['Authorization'] = 'Bearer $apiKey';
      if (id == 'openrouter') {
        req.headers['HTTP-Referer'] =
            'https://github.com/himangshurajg-bit/Personal-agentic-ai';
        req.headers['X-Title'] = 'Personal Agentic AI';
      }
      req.body = jsonEncode({
        'model': model.trim(),
        'stream': false,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
      });
    }
    return req;
  }

  String parseResponse(Map<String, dynamic> body) {
    if (id == 'gemini') {
      final candidates = body['candidates'];
      if (candidates is! List ||
          candidates.isEmpty ||
          candidates.first is! Map) {
        throw const ProviderCompareException('Provider returned no answer.');
      }
      final content = (candidates.first as Map)['content'];
      final parts = content is Map ? content['parts'] : null;
      if (parts is! List) {
        throw const ProviderCompareException(
          'Provider returned no answer text.',
        );
      }
      final text = parts
          .whereType<Map>()
          .map((p) => p['text'])
          .whereType<String>()
          .join();
      if (text.trim().isEmpty) {
        throw const ProviderCompareException(
          'Provider returned no answer text.',
        );
      }
      return text;
    }
    final choices = body['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      throw const ProviderCompareException('Provider returned no answer.');
    }
    final message = (choices.first as Map)['message'];
    final content = message is Map ? message['content'] : null;
    if (content is String && content.trim().isNotEmpty) return content;
    throw const ProviderCompareException('Provider returned no answer text.');
  }
}

class ProviderCompareException implements Exception {
  final String message;
  const ProviderCompareException(this.message);
  @override
  String toString() => message;
}

class ProviderCompareResult {
  final String providerId;
  final String providerName;
  final String? answer;
  final String? error;
  const ProviderCompareResult({
    required this.providerId,
    required this.providerName,
    this.answer,
    this.error,
  });
}

/// Only called after the UI has reviewed and approved this exact provider set/prompt.
class ProviderCompareService {
  final http.Client Function() clientFactory;
  const ProviderCompareService(this.clientFactory);

  Future<List<ProviderCompareResult>> run({
    required List<AIProviderProfile> profiles,
    required String prompt,
    required bool approvedThisRun,
  }) async {
    if (!approvedThisRun) {
      throw const ProviderCompareException(
        'Review and approve this comparison first. No request was sent.',
      );
    }
    if (prompt.trim().isEmpty || prompt.length > 8000) {
      throw const ProviderCompareException(
        'Choose a prompt of 1–8,000 characters. No request was sent.',
      );
    }
    if (profiles.length < 2 ||
        profiles.map((p) => p.id).toSet().length != profiles.length) {
      throw const ProviderCompareException(
        'Select at least two different providers. No request was sent.',
      );
    }
    // Construct and validate all requests before starting any provider call.
    final requests = profiles.map((p) => (p, p.request(prompt))).toList();
    return Future.wait(requests.map((entry) => _runOne(entry.$1, entry.$2)));
  }

  Future<ProviderCompareResult> _runOne(
    AIProviderProfile profile,
    http.Request request,
  ) async {
    final client = clientFactory();
    try {
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 60));
      final responseBytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 20),
      )) {
        if (responseBytes.length + chunk.length > 1024 * 1024) {
          return ProviderCompareResult(
            providerId: profile.id,
            providerName: profile.name,
            error: 'Provider response exceeded the 1 MiB safety limit.',
          );
        }
        responseBytes.addAll(chunk);
      }
      final raw = utf8.decode(responseBytes, allowMalformed: false);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return ProviderCompareResult(
          providerId: profile.id,
          providerName: profile.name,
          error: 'Request failed (${response.statusCode}); it was not retried.',
        );
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return ProviderCompareResult(
          providerId: profile.id,
          providerName: profile.name,
          error: 'Provider returned an unreadable response.',
        );
      }
      return ProviderCompareResult(
        providerId: profile.id,
        providerName: profile.name,
        answer: profile.parseResponse(decoded),
      );
    } on TimeoutException {
      return ProviderCompareResult(
        providerId: profile.id,
        providerName: profile.name,
        error: 'Timed out; no automatic retry was made.',
      );
    } on ProviderCompareException catch (e) {
      return ProviderCompareResult(
        providerId: profile.id,
        providerName: profile.name,
        error: e.message,
      );
    } catch (_) {
      return ProviderCompareResult(
        providerId: profile.id,
        providerName: profile.name,
        error: 'Could not complete this provider request; it was not retried.',
      );
    } finally {
      client.close();
    }
  }
}
