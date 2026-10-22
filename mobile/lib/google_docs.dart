import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'google_sign_in_setup.dart';

/// User-triggered Google Docs access restricted to files used with this app.
/// Docs and Drive intentionally share Google's single drive.file scope.
class GoogleDocsConnector {
  GoogleDocsConnector({
    GoogleDocsSecretStore? storage,
    http.Client Function()? clientFactory,
    GoogleDocsAuthorizer? authorizer,
    DateTime Function()? now,
  }) : _storage = storage ?? FlutterSecureDocsSecretStore(),
       _clientFactory = clientFactory ?? http.Client.new,
       _authorizer = authorizer ?? GoogleDocsGoogleSignInAuthorizer(),
       _now = now ?? DateTime.now;

  static const String fileScope = 'https://www.googleapis.com/auth/drive.file';
  static const String _docsRoot = 'https://docs.googleapis.com/v1';
  static const String _driveRoot = 'https://www.googleapis.com/drive/v3';
  static const String _uploadRoot =
      'https://www.googleapis.com/upload/drive/v3';
  static const String _tokenKey = 'google_docs_access_token';
  static const String _savedAtKey = 'google_docs_token_saved_at';
  static const String _emailKey = 'google_docs_email';
  static const Duration _tokenLifetime = Duration(minutes: 55);
  static const int maxTextBytes = 200 * 1024;
  static const int maxDocumentsPerLoad = 25;
  static const String _appPropertyKey = 'personalAssistantDoc';
  static const String _appPropertyValue = '1';
  static const String documentMimeType = 'application/vnd.google-apps.document';

  final GoogleDocsSecretStore _storage;
  final http.Client Function() _clientFactory;
  final GoogleDocsAuthorizer _authorizer;
  final DateTime Function() _now;
  final Set<String> _selectedOrCreatedIds = <String>{};

  Future<String?> get connectedEmail async {
    final email = await _storage.read(key: _emailKey);
    final token = await _storage.read(key: _tokenKey);
    final savedAt = int.tryParse(await _storage.read(key: _savedAtKey) ?? '');
    if (email == null || token == null || savedAt == null) return null;
    final age = _now().difference(DateTime.fromMillisecondsSinceEpoch(savedAt));
    if (age.isNegative || age >= _tokenLifetime) {
      await _clearSavedCredentials();
      _selectedOrCreatedIds.clear();
      return null;
    }
    return email;
  }

  /// Requests only drive.file when the person taps Connect.
  Future<void> connect() async {
    final credentials = await _authorizer.authorize([fileScope]);
    if (credentials.email.isEmpty || credentials.accessToken.isEmpty) {
      throw const GoogleDocsException(
        'Google did not return an account and access token. Nothing was connected.',
      );
    }
    try {
      await _storage.write(
        key: _savedAtKey,
        value: _now().millisecondsSinceEpoch.toString(),
      );
      await _storage.write(key: _emailKey, value: credentials.email);
      // The token is written last so incomplete metadata can never make it usable.
      await _storage.write(key: _tokenKey, value: credentials.accessToken);
    } catch (_) {
      await _clearSavedCredentials();
      rethrow;
    }
  }

  /// Clears only this connector's local token copy. Since Drive uses the same
  /// OAuth scope, this deliberately does not revoke/clear the shared grant/token.
  Future<void> disconnect() async {
    _selectedOrCreatedIds.clear();
    await _clearSavedCredentials();
  }

  /// Lists only Google Docs tagged as created by this app; no general Drive scan.
  Future<List<GoogleDocFile>> listCreatedDocuments() async {
    final uri = Uri.parse('$_driveRoot/files').replace(
      queryParameters: {
        'q':
            "mimeType = '$documentMimeType' and appProperties has { key='$_appPropertyKey' and value='$_appPropertyValue' } and trashed = false",
        'pageSize': '$maxDocumentsPerLoad',
        'orderBy': 'modifiedTime desc',
        'fields': 'files(id,name,mimeType,modifiedTime,appProperties)',
      },
    );
    final json = await _requestJson('GET', uri);
    final documents = ((json['files'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => GoogleDocFile.fromJson(Map<String, dynamic>.from(item)))
        .where((doc) => doc.id.isNotEmpty && doc.title.isNotEmpty)
        .toList(growable: false);
    _selectedOrCreatedIds
      ..clear()
      ..addAll(documents.map((doc) => doc.id));
    return documents;
  }

  /// Imports the user's typed text into a new native Google Doc in one request.
  /// Drive officially supports plain-text-to-Docs conversion and appProperties.
  Future<GoogleDocFile> createDocument({
    required String title,
    required String text,
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty || cleanTitle.length > 120) {
      throw const GoogleDocsException(
        'Choose a document title from 1 to 120 characters.',
      );
    }
    final textBytes = utf8.encode(text);
    if (textBytes.length > maxTextBytes) {
      throw const GoogleDocsException('Document text must be 200 KB or less.');
    }
    final boundary = 'personal_assistant_doc_${_now().microsecondsSinceEpoch}';
    final metadata = jsonEncode({
      'name': cleanTitle,
      'mimeType': documentMimeType,
      'appProperties': {_appPropertyKey: _appPropertyValue},
    });
    final body = BytesBuilder(copy: false)
      ..add(
        utf8.encode(
          '--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$metadata\r\n',
        ),
      )
      ..add(
        utf8.encode(
          '--$boundary\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\n',
        ),
      )
      ..add(textBytes)
      ..add(utf8.encode('\r\n--$boundary--\r\n'));
    final uri = Uri.parse('$_uploadRoot/files').replace(
      queryParameters: {
        'uploadType': 'multipart',
        'fields': 'id,name,mimeType,modifiedTime,appProperties',
      },
    );
    final response = await _requestBytes(
      'POST',
      uri,
      body: body.takeBytes(),
      headers: {'Content-Type': 'multipart/related; boundary=$boundary'},
    );
    final document = GoogleDocFile.fromJson(_decodeJson(response.bodyBytes));
    if (document.id.isEmpty || document.mimeType != documentMimeType) {
      throw const GoogleDocsException(
        'Google did not confirm the new document. Check Drive before retrying.',
      );
    }
    _selectedOrCreatedIds.add(document.id);
    return document;
  }

  /// Reads one document only after its row was explicitly selected from the app list.
  Future<GoogleDocContent> readSelectedDocument(String documentId) async {
    _requireSelected(documentId);
    final uri = Uri.parse(
      '$_docsRoot/documents/${Uri.encodeComponent(documentId)}',
    );
    final json = await _requestJson('GET', uri);
    return GoogleDocContent(
      id: json['documentId'] is String
          ? json['documentId'] as String
          : documentId,
      title: json['title'] is String
          ? json['title'] as String
          : 'Untitled document',
      text: _documentText(json),
      endIndex: _bodyEndIndex(json),
    );
  }

  /// Replaces text only after the user has selected an app-created document and
  /// explicitly taps Save. The fresh GET avoids applying a stale index range.
  Future<void> replaceSelectedDocumentText({
    required String documentId,
    required String text,
  }) async {
    _requireSelected(documentId);
    if (text.trim().isEmpty || utf8.encode(text).length > maxTextBytes) {
      throw const GoogleDocsException(
        'Enter document text (up to 200 KB) before saving.',
      );
    }
    final current = await readSelectedDocument(documentId);
    final requests = <Map<String, Object?>>[];
    if (current.endIndex > 2) {
      requests.add({
        'deleteContentRange': {
          'range': {'startIndex': 1, 'endIndex': current.endIndex - 1},
        },
      });
    }
    requests.add({
      'insertText': {
        'location': {'index': 1},
        'text': text,
      },
    });
    final uri = Uri.parse(
      '$_docsRoot/documents/${Uri.encodeComponent(documentId)}:batchUpdate',
    );
    await _requestJson('POST', uri, body: {'requests': requests});
  }

  void _requireSelected(String documentId) {
    if (documentId.isEmpty || !_selectedOrCreatedIds.contains(documentId)) {
      throw const GoogleDocsException(
        'Load this app’s Google Docs list and choose a document first.',
      );
    }
  }

  String _documentText(Map<String, dynamic> document) {
    final output = StringBuffer();
    void visit(List<dynamic>? elements) {
      if (elements == null) return;
      for (final raw in elements) {
        if (raw is! Map) continue;
        final element = Map<String, dynamic>.from(raw);
        final paragraph = element['paragraph'];
        if (paragraph is Map) {
          final paragraphElements = paragraph['elements'];
          if (paragraphElements is List) {
            for (final piece in paragraphElements) {
              if (piece is Map && piece['textRun'] is Map) {
                final value = (piece['textRun'] as Map)['content'];
                if (value is String) output.write(value);
              }
            }
          }
        }
        final table = element['table'];
        if (table is Map && table['tableRows'] is List) {
          for (final row in table['tableRows'] as List) {
            if (row is! Map || row['tableCells'] is! List) continue;
            for (final cell in row['tableCells'] as List) {
              if (cell is Map && cell['content'] is List) {
                visit(List<dynamic>.from(cell['content'] as List));
              }
            }
          }
        }
        final toc = element['tableOfContents'];
        if (toc is Map && toc['content'] is List) {
          visit(List<dynamic>.from(toc['content'] as List));
        }
      }
    }

    final body = document['body'];
    if (body is Map && body['content'] is List) {
      visit(List<dynamic>.from(body['content'] as List));
    }
    return output.toString();
  }

  int _bodyEndIndex(Map<String, dynamic> document) {
    final body = document['body'];
    if (body is Map && body['content'] is List) {
      final content = body['content'] as List;
      for (final item in content.reversed) {
        if (item is Map && item['endIndex'] is int) {
          return item['endIndex'] as int;
        }
      }
    }
    // An empty Docs body still has the required terminal newline at index 1.
    return 2;
  }

  Future<Map<String, dynamic>> _requestJson(
    String method,
    Uri uri, {
    Map<String, Object?>? body,
  }) async {
    final response = await _requestBytes(
      method,
      uri,
      body: body == null ? null : utf8.encode(jsonEncode(body)),
      headers: body == null
          ? const {}
          : const {'Content-Type': 'application/json; charset=utf-8'},
    );
    if (response.bodyBytes.isEmpty) return <String, dynamic>{};
    return _decodeJson(response.bodyBytes);
  }

  Map<String, dynamic> _decodeJson(List<int> bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Return one bounded connector error below.
    }
    throw const GoogleDocsException('Google returned an unexpected response.');
  }

  Future<http.Response> _requestBytes(
    String method,
    Uri uri, {
    List<int>? body,
    Map<String, String> headers = const {},
  }) async {
    final token = await _usableToken();
    final client = _clientFactory();
    try {
      final request = http.Request(method, uri)
        ..followRedirects = false
        ..headers.addAll({
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          ...headers,
        });
      if (body != null) request.bodyBytes = body;
      final streamed = await client
          .send(request)
          .timeout(const Duration(seconds: 20));
      final response = await http.Response.fromStream(streamed)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 401) {
        await _clearSavedCredentials();
        _selectedOrCreatedIds.clear();
        throw const GoogleDocsException(
          'Google Docs access expired or was revoked. Reconnect to continue; no request was retried.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw GoogleDocsException(
          'Google Docs returned HTTP ${response.statusCode}. Check Docs/Drive API setup and access; nothing was retried.',
        );
      }
      return response;
    } on GoogleDocsException {
      rethrow;
    } catch (_) {
      throw const GoogleDocsException(
        'Google Docs could not be reached. Check your connection and check Drive before retrying a document change.',
      );
    } finally {
      client.close();
    }
  }

  Future<String> _usableToken() async {
    final token = await _storage.read(key: _tokenKey);
    final savedAt = int.tryParse(await _storage.read(key: _savedAtKey) ?? '');
    if (token == null || token.isEmpty || savedAt == null) {
      throw const GoogleDocsException('Connect Google Docs first.');
    }
    final age = _now().difference(DateTime.fromMillisecondsSinceEpoch(savedAt));
    if (age.isNegative || age >= _tokenLifetime) {
      await _clearSavedCredentials();
      _selectedOrCreatedIds.clear();
      throw const GoogleDocsException(
        'Google Docs access expired. Reconnect from this screen; no request was sent.',
      );
    }
    return token;
  }

  Future<void> _clearSavedCredentials() async => Future.wait([
    _storage.delete(key: _tokenKey),
    _storage.delete(key: _savedAtKey),
    _storage.delete(key: _emailKey),
  ]);
}

class GoogleDocsGoogleSignInAuthorizer implements GoogleDocsAuthorizer {
  GoogleDocsGoogleSignInAuthorizer({String? serverClientId})
    : serverClientId =
          serverClientId ??
          const String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  final String serverClientId;

  @override
  Future<GoogleDocsCredentials> authorize(List<String> scopes) async {
    if (serverClientId.trim().isEmpty) {
      throw const GoogleDocsException(
        'Google Docs is not configured yet. Add the Google OAuth Web client ID and Android signing SHA-1 described in the setup guide.',
      );
    }
    await GoogleSignInSetup.initialize(serverClientId.trim());
    try {
      final user = await GoogleSignIn.instance.authenticate();
      final authorization = await user.authorizationClient.authorizeScopes(
        scopes,
      );
      return GoogleDocsCredentials(
        email: user.email,
        accessToken: authorization.accessToken,
      );
    } on GoogleSignInException catch (error) {
      throw GoogleDocsException(
        error.code == GoogleSignInExceptionCode.canceled
            ? 'Google sign-in was canceled. Nothing was connected.'
            : 'Google sign-in failed (${error.code.name}). Check OAuth setup and try again.',
      );
    } catch (_) {
      throw const GoogleDocsException(
        'Google sign-in could not finish. Check OAuth client, Android package/SHA-1, and Google Docs/Drive API setup.',
      );
    }
  }
}

abstract interface class GoogleDocsSecretStore {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String value});
  Future<void> delete({required String key});
}

class FlutterSecureDocsSecretStore implements GoogleDocsSecretStore {
  FlutterSecureDocsSecretStore([FlutterSecureStorage? storage])
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

abstract interface class GoogleDocsAuthorizer {
  Future<GoogleDocsCredentials> authorize(List<String> scopes);
}

class GoogleDocsCredentials {
  const GoogleDocsCredentials({required this.email, required this.accessToken});
  final String email;
  final String accessToken;
}

class GoogleDocFile {
  const GoogleDocFile({
    required this.id,
    required this.title,
    this.mimeType = GoogleDocsConnector.documentMimeType,
    this.modifiedTime,
  });
  final String id;
  final String title;
  final String mimeType;
  final DateTime? modifiedTime;

  factory GoogleDocFile.fromJson(Map<String, dynamic> json) => GoogleDocFile(
    id: json['id'] is String ? json['id'] as String : '',
    title: json['name'] is String ? json['name'] as String : '',
    mimeType: json['mimeType'] is String
        ? json['mimeType'] as String
        : GoogleDocsConnector.documentMimeType,
    modifiedTime: json['modifiedTime'] is String
        ? DateTime.tryParse(json['modifiedTime'] as String)
        : null,
  );
}

class GoogleDocContent {
  const GoogleDocContent({
    required this.id,
    required this.title,
    required this.text,
    required this.endIndex,
  });
  final String id;
  final String title;
  final String text;
  final int endIndex;
}

class GoogleDocsException implements Exception {
  const GoogleDocsException(this.message);
  final String message;
  @override
  String toString() => message;
}
