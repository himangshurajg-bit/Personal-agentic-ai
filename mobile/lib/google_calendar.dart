import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'google_sign_in_setup.dart';

/// Read-only, user-triggered Google Calendar access to the primary calendar.
/// This connector never creates, changes, or deletes events.
class GoogleCalendarConnector {
  GoogleCalendarConnector({
    GoogleCalendarSecretStore? storage,
    http.Client Function()? clientFactory,
    GoogleCalendarAuthorizer? authorizer,
    DateTime Function()? now,
  }) : _storage = storage ?? FlutterSecureCalendarSecretStore(),
       _clientFactory = clientFactory ?? http.Client.new,
       _authorizer = authorizer ?? GoogleCalendarGoogleSignInAuthorizer(),
       _now = now ?? DateTime.now;

  static const String readonlyScope =
      'https://www.googleapis.com/auth/calendar.events.readonly';
  static const String _apiRoot = 'https://www.googleapis.com/calendar/v3';
  static const String _tokenKey = 'google_calendar_access_token';
  static const String _savedAtKey = 'google_calendar_token_saved_at';
  static const String _emailKey = 'google_calendar_email';
  static const Duration _tokenLifetime = Duration(minutes: 55);

  final GoogleCalendarSecretStore _storage;
  final http.Client Function() _clientFactory;
  final GoogleCalendarAuthorizer _authorizer;
  final DateTime Function() _now;

  /// Returns an account only while its on-device access token is still usable.
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

  /// Starts Google account selection/Calendar consent only from an explicit tap.
  Future<void> connectReadOnly() async {
    final credentials = await _authorizer.authorize([readonlyScope]);
    if (credentials.accessToken.isEmpty || credentials.email.isEmpty) {
      throw const GoogleCalendarException(
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

  /// Removes just this connector's token; it does not sign out other Google features.
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

  Future<List<GoogleCalendarEvent>> listUpcomingEvents({int limit = 20}) async {
    if (limit < 1 || limit > 100) {
      throw const GoogleCalendarException('Choose between 1 and 100 events.');
    }
    final now = _now().toUtc().toIso8601String();
    final uri = Uri.parse('$_apiRoot/calendars/primary/events').replace(
      queryParameters: {
        'timeMin': now,
        'maxResults': '$limit',
        'orderBy': 'startTime',
        'singleEvents': 'true',
        'showDeleted': 'false',
        'fields': 'items(id,summary,start,end,location,status)',
      },
    );
    final response = await _request(uri);
    return ((response['items'] as List?) ?? const [])
        .whereType<Map>()
        .map(
          (item) =>
              GoogleCalendarEvent.fromJson(Map<String, dynamic>.from(item)),
        )
        .where((event) => event.status != 'cancelled')
        .toList();
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
        throw const GoogleCalendarException(
          'Google Calendar access expired or was revoked. Reconnect to continue; no request was retried.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw GoogleCalendarException(
          'Google Calendar returned HTTP ${response.statusCode}. Check API setup and access; nothing was retried.',
        );
      }
      if (response.body.isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const GoogleCalendarException(
          'Google Calendar returned an unexpected response.',
        );
      }
      return Map<String, dynamic>.from(decoded);
    } on GoogleCalendarException {
      rethrow;
    } catch (_) {
      throw const GoogleCalendarException(
        'Google Calendar could not be reached. Check your connection and try again.',
      );
    } finally {
      client.close();
    }
  }

  Future<String> _usableToken() async {
    final token = await _storage.read(key: _tokenKey);
    final savedAt = int.tryParse(await _storage.read(key: _savedAtKey) ?? '');
    if (token == null || token.isEmpty || savedAt == null) {
      throw const GoogleCalendarException('Connect Google Calendar first.');
    }
    final age = _now().difference(DateTime.fromMillisecondsSinceEpoch(savedAt));
    if (age.isNegative || age >= _tokenLifetime) {
      await _clearSavedCredentials();
      throw const GoogleCalendarException(
        'Google Calendar access expired. Reconnect from this screen; nothing was sent.',
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

class GoogleCalendarGoogleSignInAuthorizer implements GoogleCalendarAuthorizer {
  GoogleCalendarGoogleSignInAuthorizer({String? serverClientId})
    : serverClientId =
          serverClientId ??
          const String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  final String serverClientId;

  @override
  Future<GoogleCalendarCredentials> authorize(List<String> scopes) async {
    if (serverClientId.trim().isEmpty) {
      throw const GoogleCalendarException(
        'Google Calendar is not configured yet. Add the Google OAuth web client ID and Android SHA-1 as described in the setup guide.',
      );
    }
    try {
      await GoogleSignInSetup.initialize(serverClientId.trim());
      // Both account selection and the distinct read-only consent happen only
      // after the user presses Connect Google Calendar.
      final user = await GoogleSignIn.instance.authenticate();
      final authorization = await user.authorizationClient.authorizeScopes(
        scopes,
      );
      return GoogleCalendarCredentials(
        email: user.email,
        accessToken: authorization.accessToken,
      );
    } on GoogleSignInException catch (error) {
      throw GoogleCalendarException(
        error.code == GoogleSignInExceptionCode.canceled
            ? 'Google sign-in was canceled. Nothing was connected.'
            : 'Google sign-in failed (${error.code.name}). Check OAuth setup and try again.',
      );
    } catch (_) {
      throw const GoogleCalendarException(
        'Google sign-in could not finish. Check the OAuth client, Android package/SHA-1, and Google Calendar API setup.',
      );
    }
  }

  @override
  Future<void> clearAuthorizationToken(String accessToken) => GoogleSignIn
      .instance
      .authorizationClient
      .clearAuthorizationToken(accessToken: accessToken);
}

abstract interface class GoogleCalendarSecretStore {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String value});
  Future<void> delete({required String key});
}

class FlutterSecureCalendarSecretStore implements GoogleCalendarSecretStore {
  FlutterSecureCalendarSecretStore([FlutterSecureStorage? storage])
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

abstract interface class GoogleCalendarAuthorizer {
  Future<GoogleCalendarCredentials> authorize(List<String> scopes);
  Future<void> clearAuthorizationToken(String accessToken);
}

class GoogleCalendarCredentials {
  const GoogleCalendarCredentials({
    required this.email,
    required this.accessToken,
  });
  final String email;
  final String accessToken;
}

class GoogleCalendarEvent {
  const GoogleCalendarEvent({
    required this.id,
    required this.summary,
    required this.start,
    required this.end,
    required this.location,
    required this.status,
    required this.allDay,
  });

  final String id;
  final String summary;
  final DateTime? start;
  final DateTime? end;
  final String? location;
  final String? status;
  final bool allDay;

  factory GoogleCalendarEvent.fromJson(Map<String, dynamic> json) {
    bool allDay = false;
    DateTime? readDate(Object? value) {
      if (value is! Map) return null;
      final fields = Map<String, dynamic>.from(value);
      final raw = fields['dateTime'] ?? fields['date'];
      if (raw is! String) return null;
      if (fields.containsKey('date') && !fields.containsKey('dateTime')) {
        allDay = true;
      }
      return DateTime.tryParse(raw);
    }

    final start = readDate(json['start']);
    final end = readDate(json['end']);
    return GoogleCalendarEvent(
      id: json['id'] as String? ?? '',
      summary: json['summary'] as String? ?? '(no title)',
      start: start,
      end: end,
      location: json['location'] as String?,
      status: json['status'] as String?,
      allDay: allDay,
    );
  }
}

class GoogleCalendarException implements Exception {
  const GoogleCalendarException(this.message);
  final String message;
  @override
  String toString() => message;
}
