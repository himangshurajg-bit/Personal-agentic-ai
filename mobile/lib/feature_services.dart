import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'gemini_models.dart';

/// The byte limit keeps the base64-expanded inline request below Google's
/// documented 20 MB inline request recommendation while avoiding file uploads.
const maxAiDocumentBytes = 12 * 1024 * 1024;

const supportedAiDocumentMimes = <String>{
  'application/pdf',
  'image/jpeg',
  'image/png',
  'image/webp',
};

class FeatureSource {
  final String title;
  final Uri uri;
  final String supportingText;

  const FeatureSource({
    required this.title,
    required this.uri,
    this.supportingText = '',
  });
}

class FeatureAnswer {
  final String text;
  final List<FeatureSource> sources;
  final List<String> searchQueries;

  const FeatureAnswer({
    required this.text,
    this.sources = const [],
    this.searchQueries = const [],
  });

  static FeatureAnswer fromGenerateContent(Map<String, dynamic> json) {
    final candidates = json['candidates'];
    final candidate = candidates is List && candidates.isNotEmpty
        ? candidates.first
        : null;
    if (candidate is! Map) {
      throw const FormatException('Gemini returned no answer.');
    }
    final content = candidate['content'];
    final parts = content is Map ? content['parts'] : null;
    final text = parts is List
        ? parts
              .whereType<Map>()
              .map((part) => part['text'])
              .whereType<String>()
              .join('\n')
              .trim()
        : '';
    if (text.isEmpty) {
      throw const FormatException('Gemini returned no readable answer.');
    }

    final metadata = candidate['groundingMetadata'];
    final chunks = metadata is Map ? metadata['groundingChunks'] : null;
    final supports = metadata is Map ? metadata['groundingSupports'] : null;
    final rawQueries = metadata is Map ? metadata['webSearchQueries'] : null;
    final searchQueries = <String>[];
    final seenQueries = <String>{};
    if (rawQueries is List) {
      for (final rawQuery in rawQueries) {
        if (rawQuery is! String) continue;
        final query = rawQuery.trim();
        if (query.isEmpty || query.length > 300 || !seenQueries.add(query)) {
          continue;
        }
        searchQueries.add(query);
        if (searchQueries.length == 8) break;
      }
    }
    final sourceTexts = <int, List<String>>{};
    if (supports is List) {
      for (final support in supports.whereType<Map>()) {
        final segment = support['segment'];
        final indices = support['groundingChunkIndices'];
        final segmentText = segment is Map ? segment['text'] : null;
        if (segmentText is! String || indices is! List) continue;
        for (final rawIndex in indices) {
          if (rawIndex is int) {
            sourceTexts
                .putIfAbsent(rawIndex, () => <String>[])
                .add(segmentText);
          }
        }
      }
    }

    final sources = <FeatureSource>[];
    final seen = <String>{};
    if (chunks is List) {
      for (var i = 0; i < chunks.length; i++) {
        final chunk = chunks[i];
        final web = chunk is Map ? chunk['web'] : null;
        final rawUrl = web is Map ? web['uri'] : null;
        final rawTitle = web is Map ? web['title'] : null;
        if (rawUrl is! String) continue;
        final uri = Uri.tryParse(rawUrl);
        if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) continue;
        if (!seen.add(uri.toString())) continue;
        final supporting = sourceTexts[i]?.join(' ');
        sources.add(
          FeatureSource(
            uri: uri,
            title: rawTitle is String && rawTitle.trim().isNotEmpty
                ? rawTitle.trim()
                : uri.host,
            supportingText: supporting ?? '',
          ),
        );
      }
    }

    // Some Gemini responses expose citations as inline annotations instead of
    // the GenerateContent groundingMetadata shape. Accept only actual HTTPS
    // citation annotations returned by Google; never extract URLs from prose.
    if (sources.isEmpty && parts is List) {
      for (final part in parts.whereType<Map>()) {
        final annotations = part['annotations'];
        if (annotations is! List) continue;
        for (final annotation in annotations.whereType<Map>()) {
          if (annotation['type'] != 'url_citation') continue;
          final rawUrl = annotation['url'];
          if (rawUrl is! String) continue;
          final uri = Uri.tryParse(rawUrl);
          if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
            continue;
          }
          if (!seen.add(uri.toString())) continue;
          final title = annotation['title'];
          sources.add(
            FeatureSource(
              uri: uri,
              title: title is String && title.trim().isNotEmpty
                  ? title.trim()
                  : uri.host,
            ),
          );
        }
      }
    }
    return FeatureAnswer(
      text: text,
      sources: List.unmodifiable(sources),
      searchQueries: List.unmodifiable(searchQueries),
    );
  }
}

class GeminiFeatureClient {
  final String model;
  final String apiKey;
  final String endpoint;
  final http.Client Function() clientFactory;

  const GeminiFeatureClient({
    required this.model,
    required this.apiKey,
    required this.clientFactory,
    this.endpoint = GeminiModels.modelsEndpoint,
  });

  void _validate() {
    if (apiKey.trim().isEmpty) {
      throw const FeatureServiceException(
        'Add a Gemini API key in Settings before using this online feature. No content was sent.',
      );
    }
    if (!GeminiModels.supports(model)) {
      throw const FeatureServiceException(
        'Select a supported Gemini model in Settings. No content was sent.',
      );
    }
    final uri = Uri.tryParse(endpoint);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const FeatureServiceException(
        'Gemini requires a verified HTTPS endpoint.',
      );
    }
  }

  http.Request documentRequest({
    required String mimeType,
    required Uint8List bytes,
    required String prompt,
  }) {
    _validate();
    if (!supportedAiDocumentMimes.contains(mimeType)) {
      throw const FeatureServiceException(
        'Choose a PDF or PNG, JPEG or WebP image.',
      );
    }
    if (bytes.isEmpty || bytes.lengthInBytes > maxAiDocumentBytes) {
      throw const FeatureServiceException(
        'This file is empty or larger than the 12 MB inline limit. Choose a smaller file; nothing was sent.',
      );
    }
    if (prompt.trim().isEmpty || prompt.length > 8000) {
      throw const FeatureServiceException(
        'Enter a question under 8,000 characters.',
      );
    }
    final uri = Uri.parse(
      '${endpoint.replaceAll(RegExp(r'/$'), '')}/$model:generateContent',
    );
    final request = http.Request('POST', uri)
      ..followRedirects = false
      ..headers['content-type'] = 'application/json'
      ..headers['x-goog-api-key'] = apiKey
      ..body = jsonEncode({
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': prompt.trim()},
              {
                'inline_data': {
                  'mime_type': mimeType,
                  'data': base64Encode(bytes),
                },
              },
            ],
          },
        ],
        'generationConfig': {'maxOutputTokens': 2048},
      });
    return request;
  }

  http.Request researchRequest(String query) {
    _validate();
    final prompt = query.trim();
    if (prompt.isEmpty || prompt.length > 4000) {
      throw const FeatureServiceException(
        'Enter a research question under 4,000 characters.',
      );
    }
    final uri = Uri.parse(
      '${endpoint.replaceAll(RegExp(r'/$'), '')}/$model:generateContent',
    );
    return http.Request('POST', uri)
      ..followRedirects = false
      ..headers['content-type'] = 'application/json'
      ..headers['x-goog-api-key'] = apiKey
      ..body = jsonEncode({
        'contents': [
          {
            'role': 'user',
            'parts': [
              {
                'text':
                    'Research this question broadly using Google Search. Search relevant angles and useful variations rather than relying on one narrow query. Give a clear, useful summary, prioritize authoritative and primary sources, distinguish verified facts from uncertainty or disagreement, and ground factual claims in returned sources. Do not claim the search is exhaustive. Question: $prompt',
              },
            ],
          },
        ],
        'tools': [
          {'google_search': <String, dynamic>{}},
        ],
        'generationConfig': {'maxOutputTokens': 2048},
      });
  }

  Future<FeatureAnswer> askDocument({
    required String mimeType,
    required Uint8List bytes,
    required String prompt,
  }) =>
      _send(documentRequest(mimeType: mimeType, bytes: bytes, prompt: prompt));

  Future<FeatureAnswer> research(String query) => _send(researchRequest(query));

  Future<FeatureAnswer> _send(http.Request request) async {
    _validate();
    final client = clientFactory();
    try {
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 60));
      final body = await response.stream.bytesToString();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw FeatureServiceException(
          'Gemini could not complete the request (HTTP ${response.statusCode}). Check model access and quota; nothing was retried.',
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FeatureServiceException(
          'Gemini returned an unreadable response.',
        );
      }
      return FeatureAnswer.fromGenerateContent(decoded);
    } on FeatureServiceException {
      rethrow;
    } on FormatException {
      throw const FeatureServiceException(
        'Gemini returned an unreadable response.',
      );
    } on Exception {
      throw const FeatureServiceException(
        'Gemini could not be reached. Check your connection; the request was not retried.',
      );
    } finally {
      client.close();
    }
  }
}

class FeatureServiceException implements Exception {
  final String message;
  const FeatureServiceException(this.message);
  @override
  String toString() => message;
}

enum VoiceFeatureCommandKind { openRoute, reminder, unsupported }

class VoiceFeatureCommand {
  final VoiceFeatureCommandKind kind;
  final String title;
  final String? route;

  const VoiceFeatureCommand._(this.kind, this.title, this.route);

  static const _routes = <String, String>{
    'chat': '/chat',
    'conversation': '/chat',
    'settings': '/settings',
    'study': '/study',
    'memory': '/memory',
    'files': '/files',
    'documents': '/files',
    'tasks': '/library',
    'library': '/library',
    'connections': '/connections',
    'voice': '/voice',
    'research': '/features/research',
    'features': '/features',
  };

  static VoiceFeatureCommand parse(String transcript) {
    final normalized = transcript
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[.!?,;]+$'), '')
        .replaceAll(RegExp(r'\s+'), ' ');
    final reminder = RegExp(
      r'^(?:please )?(?:remind me to|set a reminder to)\s+(.+)$',
    ).firstMatch(normalized);
    if (reminder != null) {
      final title = reminder.group(1)!.trim();
      if (title.isNotEmpty && title.length <= 120) {
        return VoiceFeatureCommand._(
          VoiceFeatureCommandKind.reminder,
          title,
          null,
        );
      }
    }
    final open = RegExp(r'^(?:please )?(?:open|show)\s+(.+)$')
        .firstMatch(normalized);
    if (open != null) {
      final target = open.group(1)!.trim();
      final route = _routes[target];
      if (route != null) {
        return VoiceFeatureCommand._(
          VoiceFeatureCommandKind.openRoute,
          target,
          route,
        );
      }
    }
    return const VoiceFeatureCommand._(
      VoiceFeatureCommandKind.unsupported,
      '',
      null,
    );
  }
}
