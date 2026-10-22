import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'google_sign_in_setup.dart';

/// User-triggered, read-only Gmail access. Message data remains in caller memory.
/// This connector never writes messages, fetches attachments, syncs, or logs bodies.
class GoogleGmailConnector {
  GoogleGmailConnector({
    GoogleGmailSecretStore? storage,
    http.Client Function()? clientFactory,
    GoogleGmailAuthorizer? authorizer,
    DateTime Function()? now,
  }) : _storage = storage ?? FlutterSecureGmailSecretStore(),
       _clientFactory = clientFactory ?? http.Client.new,
       _authorizer = authorizer ?? GoogleGmailGoogleSignInAuthorizer(),
       _now = now ?? DateTime.now;

  /// Gmail's narrowest general-purpose scope for reading message bodies.
  /// Google classifies this scope as restricted.
  static const String readonlyScope =
      'https://www.googleapis.com/auth/gmail.readonly';
  static const String _apiRoot = 'https://gmail.googleapis.com/gmail/v1';
  static const String _tokenKey = 'google_gmail_access_token';
  static const String _savedAtKey = 'google_gmail_token_saved_at';
  static const String _emailKey = 'google_gmail_email';
  static const Duration _tokenLifetime = Duration(minutes: 55);
  static const int maxMessagesPerLoad = 10;
  static const int maxResponseBytes = 2 * 1024 * 1024;

  final GoogleGmailSecretStore _storage;
  final http.Client Function() _clientFactory;
  final GoogleGmailAuthorizer _authorizer;
  final DateTime Function() _now;
  final Set<String> _loadedMessageIds = <String>{};

  Future<String?> get connectedEmail async {
    final email = await _storage.read(key: _emailKey);
    final token = await _storage.read(key: _tokenKey);
    final savedAt = int.tryParse(await _storage.read(key: _savedAtKey) ?? '');
    if (email == null || token == null || savedAt == null) return null;
    final age = _now().difference(DateTime.fromMillisecondsSinceEpoch(savedAt));
    if (age.isNegative || age >= _tokenLifetime) {
      await _clearSavedCredentials();
      _loadedMessageIds.clear();
      return null;
    }
    return email;
  }

  /// Requests only gmail.readonly after the user explicitly chooses Connect.
  Future<void> connectReadOnly() async {
    final credentials = await _authorizer.authorize([readonlyScope]);
    if (credentials.email.isEmpty || credentials.accessToken.isEmpty) {
      throw const GoogleGmailException(
        'Google did not return an account and access token. Nothing was connected.',
      );
    }
    try {
      await _storage.write(
        key: _savedAtKey,
        value: _now().millisecondsSinceEpoch.toString(),
      );
      await _storage.write(key: _emailKey, value: credentials.email);
      // The bearer token is written last; partial metadata is never usable.
      await _storage.write(key: _tokenKey, value: credentials.accessToken);
    } catch (_) {
      await _clearSavedCredentials();
      rethrow;
    }
  }

  /// Removes only this connector's local credentials and transient message ids.
  Future<void> disconnect() async {
    final token = await _storage.read(key: _tokenKey);
    try {
      if (token != null && token.isNotEmpty) {
        await _authorizer.clearAuthorizationToken(token);
      }
    } finally {
      _loadedMessageIds.clear();
      await _clearSavedCredentials();
    }
  }

  /// Fetches at most ten recent Inbox message headers after a visible user action.
  /// It does not fetch message bodies; opening a row is a separate explicit read.
  Future<List<GoogleGmailMessage>> loadRecentInbox() async {
    final uri = Uri.parse('$_apiRoot/users/me/messages').replace(
      queryParameters: {
        'q': 'in:inbox -in:spam -in:trash',
        'maxResults': '$maxMessagesPerLoad',
        'fields': 'messages(id,threadId)',
      },
    );
    final listing = await _requestJson(uri);
    final rawMessages = listing['messages'];
    if (rawMessages is! List) {
      _loadedMessageIds.clear();
      return const [];
    }

    final summaries = <GoogleGmailMessage>[];
    final ids = <String>{};
    for (final raw in rawMessages.take(maxMessagesPerLoad)) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final id = item['id'];
      if (id is! String || id.isEmpty || !ids.add(id)) continue;
      final threadId = item['threadId'] is String
          ? item['threadId'] as String
          : '';
      summaries.add(await _loadHeaders(id, threadId));
    }
    _loadedMessageIds
      ..clear()
      ..addAll(summaries.map((item) => item.id));
    return summaries;
  }

  /// Fetches one complete message only after the user selects a listed row.
  /// Attachments are not downloaded and nothing is persisted by this connector.
  Future<GoogleGmailMessageBody> readSelectedMessage(String messageId) async {
    if (!_loadedMessageIds.contains(messageId)) {
      throw const GoogleGmailException(
        'Load recent inbox messages and select one first.',
      );
    }
    final uri = Uri.parse(
      '$_apiRoot/users/me/messages/${Uri.encodeComponent(messageId)}',
    ).replace(queryParameters: {'format': 'full', 'fields': 'id,payload'});
    final json = await _requestJson(uri);
    final payload = json['payload'];
    if (payload is! Map) {
      throw const GoogleGmailException(
        'Google did not return a readable message body.',
      );
    }
    final parts = <Map<String, dynamic>>[];
    _collectParts(Map<String, dynamic>.from(payload), parts);
    for (final part in parts) {
      final mimeType = (part['mimeType'] as String? ?? '').toLowerCase();
      final filename = (part['filename'] as String? ?? '').trim();
      final headers = part['headers'];
      final disposition = headers is List
          ? headers
                .whereType<Map>()
                .map((header) {
                  final entry = Map<String, dynamic>.from(header);
                  return entry['name']?.toString().toLowerCase() ==
                          'content-disposition'
                      ? entry['value']?.toString().toLowerCase() ?? ''
                      : '';
                })
                .join(' ')
          : '';
      if (mimeType != 'text/plain' ||
          filename.isNotEmpty ||
          disposition.contains('attachment')) {
        continue;
      }
      final body = part['body'];
      if (body is! Map) continue;
      final encoded = body['data'];
      if (encoded is! String || encoded.isEmpty) continue;
      try {
        return GoogleGmailMessageBody(
          messageId: messageId,
          text: utf8.decode(base64Url.decode(base64Url.normalize(encoded))),
          isPlainText: true,
        );
      } on FormatException {
        throw const GoogleGmailException(
          'Google returned an unreadable message body; it was not saved.',
        );
      }
    }
    return GoogleGmailMessageBody(
      messageId: messageId,
      text: 'This email has no inline plain-text body. Attachments were not downloaded.',
      isPlainText: false,
    );
  }

  Future<GoogleGmailMessage> _loadHeaders(String id, String threadId) async {
    final uri =
        Uri.parse('$_apiRoot/users/me/messages/${Uri.encodeComponent(id)}')
            .replace(
              queryParameters: {
                'format': 'metadata',
                'metadataHeaders': ['From', 'Subject', 'Date'],
                'fields': 'id,threadId,payload(headers)',
              },
            );
    final json = await _requestJson(uri);
    final payload = json['payload'];
    final headers = <String, String>{};
    if (payload is Map && payload['headers'] is List) {
      for (final raw in payload['headers'] as List) {
        if (raw is! Map) continue;
        final header = Map<String, dynamic>.from(raw);
        final name = header['name'];
        final value = header['value'];
        if (name is String && value is String) {
          headers[name.toLowerCase()] = value;
        }
      }
    }
    return GoogleGmailMessage(
      id: id,
      threadId: json['threadId'] is String
          ? json['threadId'] as String
          : threadId,
      from: headers['from'] ?? 'Unknown sender',
      subject: headers['subject'] ?? '(no subject)',
      date: headers['date'] ?? '',
    );
  }

  void _collectParts(
    Map<String, dynamic> part,
    List<Map<String, dynamic>> out,
  ) {
    out.add(part);
    final children = part['parts'];
    if (children is! List) return;
    for (final child in children) {
      if (child is Map) _collectParts(Map<String, dynamic>.from(child), out);
    }
  }

  Future<Map<String, dynamic>> _requestJson(Uri uri) async {
    final token = await _usableToken();
    final client = _clientFactory();
    try {
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..headers.addAll({
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        });
      final streamed = await client
          .send(request)
          .timeout(const Duration(seconds: 20));
      final bytes = await _readBounded(streamed);
      if (streamed.statusCode == 401) {
        await disconnect();
        throw const GoogleGmailException(
          'Gmail access expired or was revoked. Reconnect to continue; no request was retried.',
        );
      }
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        throw GoogleGmailException(
          'Gmail API returned HTTP ${streamed.statusCode}. Check Gmail API and OAuth setup; nothing was retried.',
        );
      }
      if (bytes.isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) {
        throw const GoogleGmailException(
          'Gmail returned an unexpected response.',
        );
      }
      return Map<String, dynamic>.from(decoded);
    } on GoogleGmailException {
      rethrow;
    } catch (_) {
      throw const GoogleGmailException(
        'Gmail could not be reached. Check your connection; no request was retried.',
      );
    } finally {
      client.close();
    }
  }

  Future<List<int>> _readBounded(http.StreamedResponse response) async {
    final builder = BytesBuilder(copy: false);
    var total = 0;
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 20),
    )) {
      total += chunk.length;
      if (total > maxResponseBytes) {
        throw const GoogleGmailException(
          'This Gmail response is over the 2 MB on-screen limit; no data was saved.',
        );
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Future<String> _usableToken() async {
    final token = await _storage.read(key: _tokenKey);
    final savedAt = int.tryParse(await _storage.read(key: _savedAtKey) ?? '');
    if (token == null || token.isEmpty || savedAt == null) {
      throw const GoogleGmailException('Connect Gmail first.');
    }
    final age = _now().difference(DateTime.fromMillisecondsSinceEpoch(savedAt));
    if (age.isNegative || age >= _tokenLifetime) {
      await _clearSavedCredentials();
      _loadedMessageIds.clear();
      throw const GoogleGmailException(
        'Gmail access expired. Reconnect from this screen; no request was sent.',
      );
    }
    return token;
  }

  Future<void> _clearSavedCredentials() => Future.wait([
    _storage.delete(key: _tokenKey),
    _storage.delete(key: _savedAtKey),
    _storage.delete(key: _emailKey),
  ]);
}

class GoogleGmailGoogleSignInAuthorizer implements GoogleGmailAuthorizer {
  GoogleGmailGoogleSignInAuthorizer({String? serverClientId})
    : serverClientId =
          serverClientId ??
          const String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  final String serverClientId;

  @override
  Future<GoogleGmailCredentials> authorize(List<String> scopes) async {
    if (serverClientId.trim().isEmpty) {
      throw const GoogleGmailException(
        'Gmail is not configured yet. Add the app-owned Google OAuth web client ID and Android SHA-1. Public Gmail access also requires restricted-scope verification.',
      );
    }
    try {
      await GoogleSignInSetup.initialize(serverClientId.trim());
      final user = await GoogleSignIn.instance.authenticate();
      final authorization = await user.authorizationClient.authorizeScopes(
        scopes,
      );
      return GoogleGmailCredentials(
        email: user.email,
        accessToken: authorization.accessToken,
      );
    } on GoogleSignInException catch (error) {
      throw GoogleGmailException(
        error.code == GoogleSignInExceptionCode.canceled
            ? 'Google sign-in was canceled. Nothing was connected.'
            : 'Google sign-in failed (${error.code.name}). Check OAuth setup and try again.',
      );
    } catch (_) {
      throw const GoogleGmailException(
        'Google sign-in could not finish. Check OAuth, Gmail API, and restricted-scope setup.',
      );
    }
  }

  @override
  Future<void> clearAuthorizationToken(String accessToken) => GoogleSignIn
      .instance
      .authorizationClient
      .clearAuthorizationToken(accessToken: accessToken);
}

abstract interface class GoogleGmailSecretStore {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String value});
  Future<void> delete({required String key});
}

class FlutterSecureGmailSecretStore implements GoogleGmailSecretStore {
  FlutterSecureGmailSecretStore([FlutterSecureStorage? storage])
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

class GoogleGmailCredentials {
  const GoogleGmailCredentials({
    required this.email,
    required this.accessToken,
  });
  final String email;
  final String accessToken;
}

abstract interface class GoogleGmailAuthorizer {
  Future<GoogleGmailCredentials> authorize(List<String> scopes);
  Future<void> clearAuthorizationToken(String accessToken);
}

class GoogleGmailMessage {
  const GoogleGmailMessage({
    required this.id,
    required this.threadId,
    required this.from,
    required this.subject,
    required this.date,
  });
  final String id;
  final String threadId;
  final String from;
  final String subject;
  final String date;
}

class GoogleGmailMessageBody {
  const GoogleGmailMessageBody({
    required this.messageId,
    required this.text,
    required this.isPlainText,
  });
  final String messageId;
  final String text;
  final bool isPlainText;
}

class GoogleGmailException implements Exception {
  const GoogleGmailException(this.message);
  final String message;
  @override
  String toString() => message;
}
