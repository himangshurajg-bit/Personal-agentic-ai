import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class ServiceException implements Exception {
  final String message;
  ServiceException(this.message);
  @override
  String toString() => message;
}

Uri checkedEndpoint(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null ||
      !uri.hasAuthority ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    throw ServiceException(
      'Enter a service origin, for example http://127.0.0.1:8766',
    );
  }
  if (uri.scheme != 'https' &&
      !(uri.scheme == 'http' &&
          const ['127.0.0.1', 'localhost', '10.0.2.2'].contains(uri.host))) {
    throw ServiceException(
      'Use HTTPS, or loopback HTTP through USB/Android emulator. Public plain HTTP is refused.',
    );
  }
  return uri;
}

class AssistantState extends ChangeNotifier {
  final FlutterSecureStorage storage;
  final http.Client Function() clientFactory;
  AssistantState({
    this.storage = const FlutterSecureStorage(),
    http.Client Function()? clientFactory,
  }) : clientFactory = clientFactory ?? http.Client.new;
  String endpoint = 'http://127.0.0.1:8766',
      token = '',
      conversation = 'personal';
  String theme = 'system', error = '', partial = '', lastPrompt = '', note = '';
  bool ready = false, onboarded = false, busy = false, speakReplies = false;
  List<Map<String, dynamic>> messages = [], memories = [];
  http.Client? _stream;
  int _generation = 0;
  static const device = MethodChannel('personal_assistant/device');
  Future<void> initialize() async {
    try {
      endpoint = await storage.read(key: 'endpoint') ?? endpoint;
      token = await storage.read(key: 'token') ?? '';
      theme = await storage.read(key: 'theme') ?? 'system';
      conversation = await storage.read(key: 'conversation') ?? 'personal';
      onboarded = await storage.read(key: 'onboarded') == 'yes';
      note = await storage.read(key: 'note') ?? '';
    } catch (_) {
      error = 'Secure storage could not be opened. Settings were not loaded.';
    }
    ready = true;
    notifyListeners();
  }

  Future<void> finishOnboarding() async {
    await storage.write(key: 'onboarded', value: 'yes');
    onboarded = true;
    notifyListeners();
  }

  Future<void> saveSettings(String url, String secret, String mode) async {
    checkedEndpoint(url);
    if (secret.isNotEmpty && secret.length < 24) {
      throw ServiceException('The service token needs at least 24 characters.');
    }
    stop();
    endpoint = url.trim().replaceAll(RegExp(r'/$'), '');
    token = secret.trim();
    theme = mode;
    await storage.write(key: 'endpoint', value: endpoint);
    await storage.write(key: 'token', value: token);
    await storage.write(key: 'theme', value: theme);
    notifyListeners();
  }

  Future<void> saveNote(String value) async {
    await storage.write(key: 'note', value: value);
    note = value;
    notifyListeners();
  }

  Map<String, String> get headers => {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };
  Future<dynamic> request(String method, String path, [Object? body]) async {
    if (token.isEmpty) {
      throw ServiceException(
        'Connect your private service in Settings first. Offline notebook is available now.',
      );
    }
    final client = clientFactory();
    try {
      final base = checkedEndpoint(endpoint);
      final req = http.Request(method, base.resolve(path))
        ..followRedirects = false;
      req.headers.addAll(headers);
      if (body != null) {
        req.body = jsonEncode(body);
      }
      final response = await client
          .send(req)
          .timeout(const Duration(seconds: 10));
      final text = await response.stream.bytesToString().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode >= 300) {
        throw ServiceException(describeStatus(response.statusCode));
      }
      return jsonDecode(text);
    } on TimeoutException {
      throw ServiceException(
        'Connection timed out. Nothing was retried. Check the service and try again.',
      );
    } on http.ClientException {
      throw ServiceException(
        'Could not reach the service. Check your connection; nothing was retried.',
      );
    } finally {
      client.close();
    }
  }

  static String describeStatus(int status) => switch (status) {
    401 => 'Service token rejected. Check Settings.',
    409 => 'This request is already running, expired or already used. Check its outcome before trying again.',
    429 => 'Too many messages. Wait one minute, then retry.',
    503 => 'No AI provider is configured. Set up a local model on the service computer; this app does not invent AI replies.',
    _ => 'Service request failed ($status). Check the service before retrying.',
  };
  Future<void> selectConversation(String id, {bool load = true}) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(id)) {
      throw ServiceException('Invalid conversation identifier.');
    }
    // Persist before switching; storage failure leaves the current scope intact.
    await storage.write(key: 'conversation', value: id);
    stop();
    conversation = id;
    messages = [];
    lastPrompt = '';
    error = '';
    notifyListeners();
    if (load) await loadHistory();
  }

  Future<void> loadHistory() async {
    try {
      messages = List<Map<String, dynamic>>.from(
        (await request(
          'GET',
          '/conversations/$conversation',
        )).map((x) => Map<String, dynamic>.from(x)),
      );
      error = '';
    } catch (e) {
      error = e.toString();
    }
    notifyListeners();
  }

  Future<void> send(String text) async {
    if (busy || text.trim().isEmpty) {
      return;
    }
    error = '';
    lastPrompt = text.trim();
    partial = '';
    busy = true;
    final generation = ++_generation;
    messages.add({'role': 'user', 'text': lastPrompt, 'state': 'complete'});
    notifyListeners();
    final client = clientFactory();
    _stream = client;
    try {
      if (token.isEmpty) {
        throw ServiceException(
          'Connect the private service in Settings first.',
        );
      }
      final req =
          http.Request('POST', checkedEndpoint(endpoint).resolve('/chat'))
            ..followRedirects = false
            ..headers.addAll(headers)
            ..body = jsonEncode({
              'conversation': conversation,
              'text': lastPrompt,
            });
      final res = await client.send(req).timeout(const Duration(seconds: 10));
      if (res.statusCode >= 300) {
        throw ServiceException(describeStatus(res.statusCode));
      }
      var done = false;
      await for (final line
          in res.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .timeout(const Duration(seconds: 65))) {
        if (generation != _generation) {
          break;
        }
        if (line.isEmpty) {
          continue;
        }
        final event = jsonDecode(line) as Map<String, dynamic>;
        if (event['type'] == 'delta') {
          partial += event['text'] as String;
          notifyListeners();
        }
        if (event['type'] == 'error') {
          throw ServiceException(event['message'] as String);
        }
        if (event['type'] == 'done') {
          done = true;
        }
      }
      if (generation == _generation) {
        if (!done) {
          throw ServiceException(
            'The reply stopped before completion. Retry only when you choose.',
          );
        }
        if (partial.isNotEmpty) {
          messages.add({
            'role': 'assistant',
            'text': partial,
            'state': 'complete',
          });
        }
        partial = '';
      }
    } catch (e) {
      if (generation == _generation) {
        error = e is TimeoutException
            ? 'The reply timed out. Check the connection and retry explicitly.'
            : e is http.ClientException
            ? 'Connection lost. No automatic retry was made.'
            : e.toString();
        if (partial.isNotEmpty) {
          messages.add({
            'role': 'assistant',
            'text': partial,
            'state': 'interrupted',
          });
          partial = '';
        }
      }
    } finally {
      client.close();
      if (generation == _generation) {
        _stream = null;
        busy = false;
        notifyListeners();
      }
    }
  }

  void stop() {
    _generation++;
    _stream?.close();
    _stream = null;
    if (partial.isNotEmpty) {
      messages.add({
        'role': 'assistant',
        'text': partial,
        'state': 'interrupted',
      });
    }
    partial = '';
    busy = false;
    notifyListeners();
  }

  Future<void> loadMemories() async {
    memories = List<Map<String, dynamic>>.from(
      (await request(
        'GET',
        '/memories',
      )).map((x) => Map<String, dynamic>.from(x)),
    );
    notifyListeners();
  }

  Future<void> remember(String fact) async {
    await request('POST', '/memories', {
      'conversation': conversation,
      'fact': fact,
    });
    await loadMemories();
  }

  Future<void> forget(String id) async {
    await request('DELETE', '/memories/$id');
    await loadMemories();
  }

  Future<String> exportMemories() async =>
      const JsonEncoder.withIndent('  ')
          .convert(await request('GET', '/memories/export'));
  @override
  void dispose() {
    _stream?.close();
    super.dispose();
  }
}
