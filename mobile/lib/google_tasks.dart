import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'google_sign_in_setup.dart';

/// User-authorized Google Tasks API adapter. It never syncs local tasks.
class GoogleTasksConnector {
  GoogleTasksConnector({
    GoogleTasksSecretStore? storage,
    http.Client Function()? clientFactory,
    GoogleTasksAuthorizer? authorizer,
    DateTime Function()? now,
  }) : _storage = storage ?? FlutterSecureTasksSecretStore(),
       _clientFactory = clientFactory ?? http.Client.new,
       _authorizer = authorizer ?? GoogleTasksGoogleSignInAuthorizer(),
       _now = now ?? DateTime.now;

  static const String readonlyScope =
      'https://www.googleapis.com/auth/tasks.readonly';
  static const String writeScope = 'https://www.googleapis.com/auth/tasks';
  static const String _apiRoot = 'https://tasks.googleapis.com/tasks/v1';
  static const String _tokenKey = 'google_tasks_access_token';
  static const String _savedAtKey = 'google_tasks_token_saved_at';
  static const String _emailKey = 'google_tasks_email';
  static const String _scopeKey = 'google_tasks_scope';
  static const Duration _tokenLifetime = Duration(minutes: 55);

  final GoogleTasksSecretStore _storage;
  final http.Client Function() _clientFactory;
  final GoogleTasksAuthorizer _authorizer;
  final DateTime Function() _now;

  Future<String?> get connectedEmail => _storage.read(key: _emailKey);
  Future<bool> get canEdit async =>
      await _storage.read(key: _scopeKey) == writeScope;

  Future<void> connectReadOnly() => _connect([readonlyScope], readonlyScope);

  /// Called only from the owner's explicit "Enable task editing" button.
  Future<void> enableEditing() => _connect([writeScope], writeScope);

  Future<void> _connect(List<String> scopes, String grantedScope) async {
    final credentials = await _authorizer.authorize(scopes);
    await _storeCredentials(credentials, grantedScope);
  }

  Future<void> _storeCredentials(
    GoogleTasksCredentials credentials,
    String scope,
  ) async {
    if (credentials.accessToken.isEmpty || credentials.email.isEmpty) {
      throw const GoogleTasksException(
        'Google did not return an account and access token. Nothing was connected.',
      );
    }
    // FlutterSecureStorage maps to platform-protected storage. Write the bearer
    // token last so incomplete metadata can never make it usable.
    try {
      await _storage.write(
        key: _savedAtKey,
        value: _now().millisecondsSinceEpoch.toString(),
      );
      await _storage.write(key: _emailKey, value: credentials.email);
      await _storage.write(key: _scopeKey, value: scope);
      await _storage.write(key: _tokenKey, value: credentials.accessToken);
    } catch (_) {
      await _clearSavedCredentials();
      rethrow;
    }
  }

  Future<void> disconnect() async {
    try {
      await _authorizer.disconnect();
    } finally {
      await _clearSavedCredentials();
    }
  }

  Future<void> _clearSavedCredentials() async {
    await Future.wait([
      _storage.delete(key: _tokenKey),
      _storage.delete(key: _savedAtKey),
      _storage.delete(key: _emailKey),
      _storage.delete(key: _scopeKey),
    ]);
  }

  Future<List<GoogleTaskList>> listTaskLists() async {
    final response = await _request('GET', 'users/@me/lists?maxResults=100');
    return ((response['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => GoogleTaskList.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<List<GoogleTask>> listTasks(String taskListId) async {
    _validateId(taskListId);
    final results = <GoogleTask>[];
    String? pageToken;
    // User-triggered, bounded pagination; never crawl a whole account in background.
    for (var page = 0; page < 10; page++) {
      final query = <String, String>{
        'maxResults': '100',
        'showCompleted': 'true',
        'showHidden': 'false',
        'pageToken': ?pageToken,
      };
      final uri = Uri.parse(
        '$_apiRoot/lists/${Uri.encodeComponent(taskListId)}/tasks',
      ).replace(queryParameters: query);
      final response = await _requestUri('GET', uri);
      results.addAll(
        ((response['items'] as List?) ?? const []).whereType<Map>().map(
          (item) => GoogleTask.fromJson(Map<String, dynamic>.from(item)),
        ),
      );
      pageToken = response['nextPageToken'] as String?;
      if (pageToken == null || pageToken.isEmpty) break;
    }
    return results;
  }

  Future<GoogleTask> addTask(String taskListId, String title) async {
    await _requireWriteScope();
    _validateId(taskListId);
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty || cleanTitle.length > 500) {
      throw const GoogleTasksException(
        'Enter a task title up to 500 characters.',
      );
    }
    final response = await _request(
      'POST',
      'lists/${Uri.encodeComponent(taskListId)}/tasks',
      body: {'title': cleanTitle},
    );
    return GoogleTask.fromJson(response);
  }

  Future<void> setTaskCompleted(
    String taskListId,
    GoogleTask task,
    bool completed,
  ) async {
    await _requireWriteScope();
    _validateId(taskListId);
    _validateId(task.id);
    await _request(
      'PATCH',
      'lists/${Uri.encodeComponent(taskListId)}/tasks/${Uri.encodeComponent(task.id)}',
      body: {'status': completed ? 'completed' : 'needsAction'},
    );
  }

  Future<void> _requireWriteScope() async {
    // A read-only grant must never be silently upgraded by a write operation.
    if (await _storage.read(key: _scopeKey) != writeScope) {
      throw const GoogleTasksException(
        'Google task editing is not enabled. Choose “Enable task editing” and approve the broader Google permission first.',
      );
    }
  }

  void _validateId(String id) {
    if (id.isEmpty ||
        id.length > 1024 ||
        id.contains('/') ||
        id.contains('..')) {
      throw const GoogleTasksException(
        'Google returned an invalid task identifier.',
      );
    }
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) => _requestUri(method, Uri.parse('$_apiRoot/$path'), body: body);

  Future<Map<String, dynamic>> _requestUri(
    String method,
    Uri uri, {
    Map<String, Object?>? body,
  }) async {
    final token = await _usableToken();
    final client = _clientFactory();
    try {
      final request = http.Request(method, uri)
        ..followRedirects = false
        ..headers.addAll({
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          if (body != null) 'Content-Type': 'application/json; charset=utf-8',
        });
      if (body != null) request.body = jsonEncode(body);
      final streamed = await client
          .send(request)
          .timeout(const Duration(seconds: 15));
      final response = await http.Response.fromStream(streamed)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 401) {
        await disconnect();
        throw const GoogleTasksException(
          'Google authorization expired or was revoked. Reconnect to continue; no request was retried.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw GoogleTasksException(
          'Google Tasks returned HTTP ${response.statusCode}. Check API setup and access; nothing was retried.',
        );
      }
      if (response.body.isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const GoogleTasksException(
          'Google Tasks returned an unexpected response.',
        );
      }
      return Map<String, dynamic>.from(decoded);
    } on GoogleTasksException {
      rethrow;
    } catch (_) {
      throw const GoogleTasksException(
        'Google Tasks could not be reached. Check your connection and try again.',
      );
    } finally {
      client.close();
    }
  }

  Future<String> _usableToken() async {
    final token = await _storage.read(key: _tokenKey);
    final savedAt = int.tryParse(await _storage.read(key: _savedAtKey) ?? '');
    if (token == null || token.isEmpty || savedAt == null) {
      throw const GoogleTasksException('Connect your Google account first.');
    }
    final age = _now().difference(DateTime.fromMillisecondsSinceEpoch(savedAt));
    if (age.isNegative || age >= _tokenLifetime) {
      await _clearSavedCredentials();
      throw const GoogleTasksException(
        'Google access expired. Reconnect from this screen; nothing was sent.',
      );
    }
    return token;
  }
}

class GoogleTasksGoogleSignInAuthorizer implements GoogleTasksAuthorizer {
  GoogleTasksGoogleSignInAuthorizer({String? serverClientId})
    : serverClientId =
          serverClientId ??
          const String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  final String serverClientId;
  @override
  Future<GoogleTasksCredentials> authorize(List<String> scopes) async {
    if (serverClientId.trim().isEmpty) {
      throw const GoogleTasksException(
        'Google Tasks is not configured yet. Add the Google OAuth web client ID and Android SHA-1 as described in the setup guide.',
      );
    }
    await GoogleSignInSetup.initialize(serverClientId.trim());
    try {
      // Called only from an explicit Connect/Enable editing user action.
      final user = await GoogleSignIn.instance.authenticate();
      final authorization = await user.authorizationClient.authorizeScopes(
        scopes,
      );
      return GoogleTasksCredentials(
        email: user.email,
        accessToken: authorization.accessToken,
      );
    } on GoogleSignInException catch (error) {
      throw GoogleTasksException(
        error.code == GoogleSignInExceptionCode.canceled
            ? 'Google sign-in was canceled. Nothing was connected.'
            : 'Google sign-in failed (${error.code.name}). Check OAuth setup and try again.',
      );
    } catch (_) {
      throw const GoogleTasksException(
        'Google sign-in could not finish. Check the OAuth client, Android package/SHA-1, and Google Tasks API setup.',
      );
    }
  }

  @override
  Future<void> disconnect() => GoogleSignIn.instance.disconnect();
}

abstract interface class GoogleTasksSecretStore {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String value});
  Future<void> delete({required String key});
}

class FlutterSecureTasksSecretStore implements GoogleTasksSecretStore {
  FlutterSecureTasksSecretStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);
  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}

abstract interface class GoogleTasksAuthorizer {
  Future<GoogleTasksCredentials> authorize(List<String> scopes);
  Future<void> disconnect();
}

class GoogleTasksCredentials {
  const GoogleTasksCredentials({
    required this.email,
    required this.accessToken,
  });
  final String email;
  final String accessToken;
}

class GoogleTaskList {
  const GoogleTaskList({required this.id, required this.title});
  final String id;
  final String title;

  factory GoogleTaskList.fromJson(Map<String, dynamic> json) => GoogleTaskList(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? 'Untitled list',
  );
}

class GoogleTask {
  const GoogleTask({
    required this.id,
    required this.title,
    required this.completed,
    this.due,
  });
  final String id;
  final String title;
  final bool completed;
  final String? due;

  factory GoogleTask.fromJson(Map<String, dynamic> json) => GoogleTask(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? 'Untitled task',
    completed: json['status'] == 'completed',
    due: json['due'] as String?,
  );
}

class GoogleTasksException implements Exception {
  const GoogleTasksException(this.message);
  final String message;
  @override
  String toString() => message;
}
