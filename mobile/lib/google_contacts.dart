import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'google_sign_in_setup.dart';

/// Explicit, read-only access to the user's saved Google Contacts.
/// Contact data is returned to the calling screen only; nothing is cached here.
class GoogleContactsConnector {
  GoogleContactsConnector({
    GoogleContactsSecretStore? storage,
    http.Client Function()? clientFactory,
    GoogleContactsAuthorizer? authorizer,
    DateTime Function()? now,
  }) : _storage = storage ?? FlutterSecureContactsSecretStore(),
       _clientFactory = clientFactory ?? http.Client.new,
       _authorizer = authorizer ?? GoogleContactsGoogleSignInAuthorizer(),
       _now = now ?? DateTime.now;

  static const String readonlyScope =
      'https://www.googleapis.com/auth/contacts.readonly';
  static const String _apiRoot = 'https://people.googleapis.com/v1';
  static const String _tokenKey = 'google_contacts_access_token';
  static const String _savedAtKey = 'google_contacts_token_saved_at';
  static const String _emailKey = 'google_contacts_email';
  static const Duration _tokenLifetime = Duration(minutes: 55);
  static const String _personFields = 'names,emailAddresses,phoneNumbers';
  static const int _pageSize = 100;
  static const int _maxPages = 3;

  final GoogleContactsSecretStore _storage;
  final http.Client Function() _clientFactory;
  final GoogleContactsAuthorizer _authorizer;
  final DateTime Function() _now;

  Future<String?> get connectedEmail async {
    final email = await _storage.read(key: _emailKey);
    final token = await _storage.read(key: _tokenKey);
    final savedAt = int.tryParse(await _storage.read(key: _savedAtKey) ?? '');
    if (email == null || token == null || savedAt == null) return null;
    final age = _now().difference(DateTime.fromMillisecondsSinceEpoch(savedAt));
    if (age.isNegative || age >= _tokenLifetime) {
      await _clearSavedCredentials();
      return null;
    }
    return email;
  }

  /// Starts a distinct contacts consent flow only after an explicit Connect tap.
  Future<void> connectReadOnly() async {
    final credentials = await _authorizer.authorize([readonlyScope]);
    if (credentials.accessToken.isEmpty || credentials.email.isEmpty) {
      throw const GoogleContactsException(
        'Google did not return an account and access token. Nothing was connected.',
      );
    }
    try {
      await _storage.write(
        key: _savedAtKey,
        value: _now().millisecondsSinceEpoch.toString(),
      );
      await _storage.write(key: _emailKey, value: credentials.email);
      // The bearer token is written last so partial metadata is never usable.
      await _storage.write(key: _tokenKey, value: credentials.accessToken);
    } catch (_) {
      await _clearSavedCredentials();
      rethrow;
    }
  }

  /// Clears only this connector's local token and plugin authorization token.
  Future<void> disconnect() async {
    final token = await _storage.read(key: _tokenKey);
    try {
      if (token != null && token.isNotEmpty) {
        await _authorizer.clearAuthorizationToken(token);
      }
    } finally {
      await _clearSavedCredentials();
    }
  }

  /// Reads at most 300 contacts, and only in response to an explicit user action.
  /// The caller may request a later refresh; this connector never background-syncs.
  Future<List<GoogleContact>> listContacts() async {
    final results = <GoogleContact>[];
    final seen = <String>{};
    String? pageToken;
    for (var page = 0; page < _maxPages; page++) {
      final uri = Uri.parse('$_apiRoot/people/me/connections').replace(
        queryParameters: {
          'pageSize': '$_pageSize',
          'personFields': _personFields,
          'requestSyncToken': 'false',
          'pageToken': ?pageToken,
          'fields': 'connections(resourceName,names,emailAddresses,phoneNumbers),nextPageToken',
        },
      );
      final response = await _request(uri);
      for (final raw in (response['connections'] as List? ?? const [])) {
        if (raw is! Map) continue;
        final contact = GoogleContact.fromJson(Map<String, dynamic>.from(raw));
        if (contact.hasDisplayValue && seen.add(contact.identity)) {
          results.add(contact);
        }
      }
      final next = response['nextPageToken'];
      pageToken = next is String && next.isNotEmpty ? next : null;
      if (pageToken == null) break;
    }
    return results;
  }

  Future<Map<String, dynamic>> _request(Uri uri) async {
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
          .timeout(const Duration(seconds: 15));
      final response = await http.Response.fromStream(streamed)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 401) {
        await disconnect();
        throw const GoogleContactsException(
          'Google Contacts access expired or was revoked. Reconnect to continue; no request was retried.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw GoogleContactsException(
          'Google People API returned HTTP ${response.statusCode}. Check API setup and access; nothing was retried.',
        );
      }
      if (response.body.isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const GoogleContactsException(
          'Google People API returned an unexpected response.',
        );
      }
      return Map<String, dynamic>.from(decoded);
    } on GoogleContactsException {
      rethrow;
    } catch (_) {
      throw const GoogleContactsException(
        'Google Contacts could not be reached. Check your connection and try again.',
      );
    } finally {
      client.close();
    }
  }

  Future<String> _usableToken() async {
    final token = await _storage.read(key: _tokenKey);
    final savedAt = int.tryParse(await _storage.read(key: _savedAtKey) ?? '');
    if (token == null || token.isEmpty || savedAt == null) {
      throw const GoogleContactsException('Connect Google Contacts first.');
    }
    final age = _now().difference(DateTime.fromMillisecondsSinceEpoch(savedAt));
    if (age.isNegative || age >= _tokenLifetime) {
      await _clearSavedCredentials();
      throw const GoogleContactsException(
        'Google Contacts access expired. Reconnect from this screen; nothing was sent.',
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

class GoogleContactsGoogleSignInAuthorizer implements GoogleContactsAuthorizer {
  GoogleContactsGoogleSignInAuthorizer({String? serverClientId})
    : serverClientId =
          serverClientId ??
          const String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  final String serverClientId;

  @override
  Future<GoogleContactsCredentials> authorize(List<String> scopes) async {
    if (serverClientId.trim().isEmpty) {
      throw const GoogleContactsException(
        'Google Contacts is not configured yet. Add the Google OAuth web client ID and Android SHA-1 as described in the setup guide.',
      );
    }
    try {
      await GoogleSignInSetup.initialize(serverClientId.trim());
      final user = await GoogleSignIn.instance.authenticate();
      final authorization = await user.authorizationClient.authorizeScopes(
        scopes,
      );
      return GoogleContactsCredentials(
        email: user.email,
        accessToken: authorization.accessToken,
      );
    } on GoogleSignInException catch (error) {
      throw GoogleContactsException(
        error.code == GoogleSignInExceptionCode.canceled
            ? 'Google sign-in was canceled. Nothing was connected.'
            : 'Google sign-in failed (${error.code.name}). Check OAuth setup and try again.',
      );
    } catch (_) {
      throw const GoogleContactsException(
        'Google sign-in could not finish. Check the OAuth client, Android package/SHA-1, and Google People API setup.',
      );
    }
  }

  @override
  Future<void> clearAuthorizationToken(String accessToken) => GoogleSignIn
      .instance
      .authorizationClient
      .clearAuthorizationToken(accessToken: accessToken);
}

abstract interface class GoogleContactsSecretStore {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String value});
  Future<void> delete({required String key});
}

class FlutterSecureContactsSecretStore implements GoogleContactsSecretStore {
  FlutterSecureContactsSecretStore([FlutterSecureStorage? storage])
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

class GoogleContactsCredentials {
  const GoogleContactsCredentials({
    required this.email,
    required this.accessToken,
  });
  final String email;
  final String accessToken;
}

abstract interface class GoogleContactsAuthorizer {
  Future<GoogleContactsCredentials> authorize(List<String> scopes);
  Future<void> clearAuthorizationToken(String accessToken);
}

class GoogleContact {
  const GoogleContact({
    required this.resourceName,
    required this.displayName,
    required this.emails,
    required this.phones,
  });

  final String resourceName;
  final String displayName;
  final List<String> emails;
  final List<String> phones;

  String get identity => resourceName.isNotEmpty
      ? resourceName
      : '${displayName.toLowerCase()}|${emails.join('|').toLowerCase()}|${phones.join('|').toLowerCase()}';
  bool get hasDisplayValue =>
      (displayName.isNotEmpty && displayName != '(unnamed contact)') ||
      emails.isNotEmpty ||
      phones.isNotEmpty;

  factory GoogleContact.fromJson(Map<String, dynamic> json) {
    final names = (json['names'] as List? ?? const []).whereType<Map>();
    String name = '';
    if (names.isNotEmpty) {
      final first = Map<String, dynamic>.from(names.first);
      name = (first['displayName'] as String? ?? '').trim();
      if (name.isEmpty) {
        name = [first['givenName'], first['familyName']]
            .whereType<String>()
            .map((part) => part.trim())
            .where((part) => part.isNotEmpty)
            .join(' ');
      }
    }
    List<String> values(String field, String property) =>
        (json[field] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item)[property])
            .whereType<String>()
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList();
    return GoogleContact(
      resourceName: json['resourceName'] as String? ?? '',
      displayName: name.isEmpty ? '(unnamed contact)' : name,
      emails: values('emailAddresses', 'value'),
      phones: values('phoneNumbers', 'value'),
    );
  }
}

class GoogleContactsException implements Exception {
  const GoogleContactsException(this.message);
  final String message;
  @override
  String toString() => message;
}
