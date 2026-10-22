import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'google_sign_in_setup.dart';

/// Explicitly user-triggered access to text files created by this app.
/// Uses Drive's narrow drive.file scope; it does not search the user's Drive.
class GoogleDriveConnector {
  GoogleDriveConnector({
    GoogleDriveSecretStore? storage,
    http.Client Function()? clientFactory,
    GoogleDriveAuthorizer? authorizer,
    DateTime Function()? now,
  }) : _storage = storage ?? FlutterSecureDriveSecretStore(),
       _clientFactory = clientFactory ?? http.Client.new,
       _authorizer = authorizer ?? GoogleDriveGoogleSignInAuthorizer(),
       _now = now ?? DateTime.now;

  static const String fileScope = 'https://www.googleapis.com/auth/drive.file';
  static const String _apiRoot = 'https://www.googleapis.com/drive/v3';
  static const String _uploadRoot =
      'https://www.googleapis.com/upload/drive/v3';
  static const String _tokenKey = 'google_drive_access_token';
  static const String _savedAtKey = 'google_drive_token_saved_at';
  static const String _emailKey = 'google_drive_email';
  static const Duration _tokenLifetime = Duration(minutes: 55);
  static const int maxTextBytes = 200 * 1024;
  static const int maxFilesPerLoad = 25;
  static const String _appPropertyKey = 'personalAssistantFile';
  static const String _appPropertyValue = '1';

  final GoogleDriveSecretStore _storage;
  final http.Client Function() _clientFactory;
  final GoogleDriveAuthorizer _authorizer;
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

  /// Requests only Drive's app-file scope after the person chooses Connect.
  Future<void> connect() async {
    final credentials = await _authorizer.authorize([fileScope]);
    if (credentials.email.isEmpty || credentials.accessToken.isEmpty) {
      throw const GoogleDriveException(
        'Google did not return an account and access token. Nothing was connected.',
      );
    }
    try {
      await _storage.write(
        key: _savedAtKey,
        value: _now().millisecondsSinceEpoch.toString(),
      );
      await _storage.write(key: _emailKey, value: credentials.email);
      await _storage.write(key: _tokenKey, value: credentials.accessToken);
    } catch (_) {
      await _clearSavedCredentials();
      rethrow;
    }
  }

  /// Disconnects this connector only; other Google services remain connected.
  Future<void> disconnect() async {
    final token = await _storage.read(key: _tokenKey);
    try {
      if (token != null && token.isNotEmpty) {
        await _authorizer.clearAuthorizationToken(token);
      }
    } finally {
      _selectedOrCreatedIds.clear();
      await _clearSavedCredentials();
    }
  }

  /// Shows only files explicitly created by this app and tagged with its private
  /// Drive appProperty. The user then chooses a returned row to open it.
  Future<List<GoogleDriveFile>> listAppFiles() async {
    final uri = Uri.parse('$_apiRoot/files').replace(
      queryParameters: {
        'q':
            "appProperties has { key='$_appPropertyKey' and value='$_appPropertyValue' } and trashed = false",
        'pageSize': '$maxFilesPerLoad',
        'orderBy': 'modifiedTime desc',
        'fields': 'files(id,name,mimeType,modifiedTime,appProperties)',
      },
    );
    final json = await _requestJson('GET', uri);
    final files = ((json['files'] as List?) ?? const [])
        .whereType<Map>()
        .map((raw) => GoogleDriveFile.fromJson(Map<String, dynamic>.from(raw)))
        .where((file) => file.id.isNotEmpty && file.name.isNotEmpty)
        .toList(growable: false);
    _selectedOrCreatedIds
      ..clear()
      ..addAll(files.map((file) => file.id));
    return files;
  }

  /// Create a plain-text file only after an explicit user action in the UI.
  Future<GoogleDriveFile> createTextFile({
    required String name,
    required String contents,
  }) async {
    final safeName = name.trim();
    if (safeName.isEmpty || safeName.length > 120) {
      throw const GoogleDriveException(
        'Choose a file name from 1 to 120 characters.',
      );
    }
    final bytes = utf8.encode(contents);
    if (bytes.isEmpty || bytes.length > maxTextBytes) {
      throw const GoogleDriveException(
        'Text files must contain 1 to 200 KB of text.',
      );
    }
    final boundary = 'wabi_drive_${_now().microsecondsSinceEpoch}';
    final metadata = jsonEncode({
      'name': safeName,
      'mimeType': 'text/plain',
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
      ..add(bytes)
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
    final file = GoogleDriveFile.fromJson(_decodeJson(response.bodyBytes));
    if (file.id.isEmpty) {
      throw const GoogleDriveException(
        'Google Drive did not return a file ID; check Drive before retrying.',
      );
    }
    _selectedOrCreatedIds.add(file.id);
    return file;
  }

  /// Read a single app-created file after the owner taps its listed row.
  Future<String> readSelectedTextFile(String fileId) async {
    if (!_selectedOrCreatedIds.contains(fileId)) {
      throw const GoogleDriveException(
        'Choose a file from the current Google Drive app-files list first.',
      );
    }
    final uri = Uri.parse('$_apiRoot/files/${Uri.encodeComponent(fileId)}')
        .replace(queryParameters: {'alt': 'media'});
    final response = await _requestBytes('GET', uri);
    try {
      return utf8.decode(response.bodyBytes);
    } on FormatException {
      throw const GoogleDriveException(
        'That file is not valid UTF-8 text and was not shown.',
      );
    }
  }

  Future<Map<String, dynamic>> _requestJson(String method, Uri uri) async {
    final response = await _requestBytes(method, uri);
    if (response.bodyBytes.isEmpty) return <String, dynamic>{};
    return _decodeJson(response.bodyBytes);
  }

  Map<String, dynamic> _decodeJson(List<int> bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Return one safe, user-facing connector error below.
    }
    throw const GoogleDriveException(
      'Google Drive returned an unexpected response.',
    );
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
          'Accept': 'application/json, text/plain;q=0.9',
          ...headers,
        });
      if (body != null) request.bodyBytes = body;
      final streamed = await client
          .send(request)
          .timeout(const Duration(seconds: 20));
      final response = await http.Response.fromStream(streamed)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 401) {
        await disconnect();
        throw const GoogleDriveException(
          'Google Drive access expired or was revoked. Reconnect to continue; no request was retried.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw GoogleDriveException(
          'Google Drive returned HTTP ${response.statusCode}. Check Drive API setup and file access; nothing was retried.',
        );
      }
      return response;
    } on GoogleDriveException {
      rethrow;
    } catch (_) {
      throw const GoogleDriveException(
        'Google Drive could not be reached. Check your connection and check Drive before retrying a file creation.',
      );
    } finally {
      client.close();
    }
  }

  Future<String> _usableToken() async {
    final token = await _storage.read(key: _tokenKey);
    final savedAt = int.tryParse(await _storage.read(key: _savedAtKey) ?? '');
    if (token == null || token.isEmpty || savedAt == null) {
      throw const GoogleDriveException('Connect Google Drive first.');
    }
    final age = _now().difference(DateTime.fromMillisecondsSinceEpoch(savedAt));
    if (age.isNegative || age >= _tokenLifetime) {
      await _clearSavedCredentials();
      _selectedOrCreatedIds.clear();
      throw const GoogleDriveException(
        'Google Drive access expired. Reconnect from this screen; no request was sent.',
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

class GoogleDriveGoogleSignInAuthorizer implements GoogleDriveAuthorizer {
  GoogleDriveGoogleSignInAuthorizer({String? serverClientId})
    : serverClientId =
          serverClientId ??
          const String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  final String serverClientId;

  @override
  Future<GoogleDriveCredentials> authorize(List<String> scopes) async {
    if (serverClientId.trim().isEmpty) {
      throw const GoogleDriveException(
        'Google Drive is not configured yet. Add the Google OAuth web client ID and Android signing SHA-1 as described in the setup guide.',
      );
    }
    try {
      await GoogleSignInSetup.initialize(serverClientId.trim());
      final user = await GoogleSignIn.instance.authenticate();
      // The new drive.file permission is requested only when Connect is tapped.
      final authorization = await user.authorizationClient.authorizeScopes(
        scopes,
      );
      return GoogleDriveCredentials(
        email: user.email,
        accessToken: authorization.accessToken,
      );
    } on GoogleSignInException catch (error) {
      throw GoogleDriveException(
        error.code == GoogleSignInExceptionCode.canceled
            ? 'Google sign-in was canceled. Nothing was connected.'
            : 'Google sign-in failed (${error.code.name}). Check OAuth setup and try again.',
      );
    } catch (_) {
      throw const GoogleDriveException(
        'Google sign-in could not finish. Check OAuth client, Android package/SHA-1, and Google Drive API setup.',
      );
    }
  }

  @override
  Future<void> clearAuthorizationToken(String accessToken) => GoogleSignIn
      .instance
      .authorizationClient
      .clearAuthorizationToken(accessToken: accessToken);
}

abstract interface class GoogleDriveSecretStore {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String value});
  Future<void> delete({required String key});
}

class FlutterSecureDriveSecretStore implements GoogleDriveSecretStore {
  FlutterSecureDriveSecretStore([FlutterSecureStorage? storage])
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

abstract interface class GoogleDriveAuthorizer {
  Future<GoogleDriveCredentials> authorize(List<String> scopes);
  Future<void> clearAuthorizationToken(String accessToken);
}

class GoogleDriveCredentials {
  const GoogleDriveCredentials({
    required this.email,
    required this.accessToken,
  });
  final String email;
  final String accessToken;
}

class GoogleDriveFile {
  const GoogleDriveFile({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.modifiedTime,
  });

  final String id;
  final String name;
  final String mimeType;
  final DateTime? modifiedTime;

  factory GoogleDriveFile.fromJson(Map<String, dynamic> json) =>
      GoogleDriveFile(
        id: json['id'] is String ? json['id'] as String : '',
        name: json['name'] is String ? json['name'] as String : '',
        mimeType: json['mimeType'] is String
            ? json['mimeType'] as String
            : 'text/plain',
        modifiedTime: json['modifiedTime'] is String
            ? DateTime.tryParse(json['modifiedTime'] as String)
            : null,
      );
}

class GoogleDriveException implements Exception {
  const GoogleDriveException(this.message);
  final String message;
  @override
  String toString() => message;
}
