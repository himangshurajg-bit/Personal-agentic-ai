import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_assistant/google_calendar.dart';

void main() {
  final fixedNow = DateTime.utc(2026, 10, 22, 7);
  late _MemorySecrets secrets;
  late _FakeAuthorizer authorizer;

  setUp(() {
    secrets = _MemorySecrets();
    authorizer = _FakeAuthorizer();
  });

  test(
    'missing OAuth setup fails closed without marking an account connected',
    () async {
      final connector = GoogleCalendarConnector(
        storage: secrets,
        authorizer: GoogleCalendarGoogleSignInAuthorizer(serverClientId: ''),
        now: () => fixedNow,
      );

      await expectLater(
        connector.connectReadOnly(),
        throwsA(
          isA<GoogleCalendarException>().having(
            (error) => error.message,
            'message',
            contains('not configured'),
          ),
        ),
      );
      expect(await connector.connectedEmail, isNull);
      expect(await secrets.read(key: 'google_calendar_access_token'), isNull);
    },
  );

  test(
    'one explicit connection requests only read-only Calendar event scope',
    () async {
      var apiCalls = 0;
      final connector = GoogleCalendarConnector(
        storage: secrets,
        authorizer: authorizer,
        now: () => fixedNow,
        clientFactory: () => MockClient((_) async {
          apiCalls++;
          return http.Response('{}', 200);
        }),
      );

      expect(await connector.connectedEmail, isNull);
      expect(authorizer.requestedScopes, isEmpty);
      expect(apiCalls, 0);
      await expectLater(
        connector.listUpcomingEvents(),
        throwsA(isA<GoogleCalendarException>()),
      );
      expect(apiCalls, 0);

      await connector.connectReadOnly();
      expect(authorizer.requestedScopes, [
        [GoogleCalendarConnector.readonlyScope],
      ]);
      expect(await connector.connectedEmail, 'himangshuraj@gmail.com');
      expect(
        await secrets.read(key: 'google_calendar_access_token'),
        'calendar-token',
      );
      expect(await secrets.read(key: 'google_tasks_access_token'), isNull);
      expect(apiCalls, 0, reason: 'Connecting must not load events.');
    },
  );

  test('explicit upcoming-events read is bounded to primary calendar and read-only', () async {
    final requests = <http.Request>[];
    final connector = GoogleCalendarConnector(
      storage: secrets,
      authorizer: authorizer,
      now: () => fixedNow,
      clientFactory: () => MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': 'event-1',
                'summary': 'Study group',
                'start': {'dateTime': '2026-10-23T14:00:00+05:30'},
                'end': {'dateTime': '2026-10-23T15:00:00+05:30'},
                'location': 'Library',
                'status': 'confirmed',
              },
              {
                'id': 'event-2',
                'summary': 'Holiday',
                'start': {'date': '2026-10-24'},
                'end': {'date': '2026-10-25'},
                'status': 'confirmed',
              },
              {
                'id': 'event-3',
                'summary': 'Canceled',
                'start': {'dateTime': '2026-10-25T09:00:00Z'},
                'end': {'dateTime': '2026-10-25T10:00:00Z'},
                'status': 'cancelled',
              },
            ],
          }),
          200,
        );
      }),
    );
    await connector.connectReadOnly();

    final events = await connector.listUpcomingEvents();
    expect(events, hasLength(2));
    expect(events.first.summary, 'Study group');
    expect(events.first.location, 'Library');
    expect(events.first.allDay, isFalse);
    expect(events.last.summary, 'Holiday');
    expect(events.last.allDay, isTrue);
    final request = requests.single;
    expect(request.method, 'GET');
    expect(request.url.path, '/calendar/v3/calendars/primary/events');
    expect(request.url.queryParameters['maxResults'], '20');
    expect(request.url.queryParameters['singleEvents'], 'true');
    expect(request.url.queryParameters['orderBy'], 'startTime');
    expect(request.url.queryParameters['timeMin'], fixedNow.toIso8601String());
    expect(request.headers['authorization'], 'Bearer calendar-token');
    expect(request.body, isEmpty);
  });

  test(
    'Calendar disconnect clears only its own token and local account metadata',
    () async {
      final connector = GoogleCalendarConnector(
        storage: secrets,
        authorizer: authorizer,
        now: () => fixedNow,
      );
      await connector.connectReadOnly();
      await secrets.write(
        key: 'google_tasks_access_token',
        value: 'tasks-token',
      );

      await connector.disconnect();

      expect(authorizer.clearedTokens, ['calendar-token']);
      expect(await connector.connectedEmail, isNull);
      expect(await secrets.read(key: 'google_calendar_access_token'), isNull);
      expect(await secrets.read(key: 'google_calendar_email'), isNull);
      expect(
        await secrets.read(key: 'google_tasks_access_token'),
        'tasks-token',
      );
    },
  );

  test('401 clears authorization and does not retry', () async {
    var calls = 0;
    final connector = GoogleCalendarConnector(
      storage: secrets,
      authorizer: authorizer,
      now: () => fixedNow,
      clientFactory: () => MockClient((_) async {
        calls++;
        return http.Response('{}', 401);
      }),
    );
    await connector.connectReadOnly();

    await expectLater(
      connector.listUpcomingEvents(),
      throwsA(isA<GoogleCalendarException>()),
    );
    expect(calls, 1);
    expect(authorizer.clearedTokens, ['calendar-token']);
    expect(await connector.connectedEmail, isNull);
    await expectLater(
      connector.listUpcomingEvents(),
      throwsA(isA<GoogleCalendarException>()),
    );
    expect(calls, 1);
  });

  test('locally expired token is removed without a network request', () async {
    var now = fixedNow;
    var calls = 0;
    final connector = GoogleCalendarConnector(
      storage: secrets,
      authorizer: authorizer,
      now: () => now,
      clientFactory: () => MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    await connector.connectReadOnly();
    now = fixedNow.add(const Duration(minutes: 56));

    expect(await connector.connectedEmail, isNull);
    await expectLater(
      connector.listUpcomingEvents(),
      throwsA(isA<GoogleCalendarException>()),
    );
    expect(calls, 0);
    expect(await secrets.read(key: 'google_calendar_access_token'), isNull);
  });
}

class _MemorySecrets implements GoogleCalendarSecretStore {
  final Map<String, String> values = {};
  @override
  Future<String?> read({required String key}) async => values[key];
  @override
  Future<void> write({required String key, required String value}) async =>
      values[key] = value;
  @override
  Future<void> delete({required String key}) async => values.remove(key);
}

class _FakeAuthorizer implements GoogleCalendarAuthorizer {
  final requestedScopes = <List<String>>[];
  final clearedTokens = <String>[];

  @override
  Future<GoogleCalendarCredentials> authorize(List<String> scopes) async {
    requestedScopes.add(List<String>.from(scopes));
    return const GoogleCalendarCredentials(
      email: 'himangshuraj@gmail.com',
      accessToken: 'calendar-token',
    );
  }

  @override
  Future<void> clearAuthorizationToken(String accessToken) async {
    clearedTokens.add(accessToken);
  }
}
