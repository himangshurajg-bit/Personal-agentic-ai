import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_assistant/google_contacts.dart';

void main() {
  final fixedNow = DateTime.utc(2026, 10, 22, 7);
  late _MemorySecrets secrets;
  late _FakeAuthorizer authorizer;

  setUp(() {
    secrets = _MemorySecrets();
    authorizer = _FakeAuthorizer();
  });

  test(
    'missing OAuth setup fails closed and does not mark connected',
    () async {
      final connector = GoogleContactsConnector(
        storage: secrets,
        authorizer: GoogleContactsGoogleSignInAuthorizer(serverClientId: ''),
        now: () => fixedNow,
      );
      await expectLater(
        connector.connectReadOnly(),
        throwsA(
          isA<GoogleContactsException>().having(
            (error) => error.message,
            'message',
            contains('not configured'),
          ),
        ),
      );
      expect(await connector.connectedEmail, isNull);
      expect(await secrets.read(key: 'google_contacts_access_token'), isNull);
    },
  );

  test(
    'explicit Connect requests only contacts.readonly and does not fetch data',
    () async {
      var requests = 0;
      final connector = GoogleContactsConnector(
        storage: secrets,
        authorizer: authorizer,
        now: () => fixedNow,
        clientFactory: () => MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );
      expect(await connector.connectedEmail, isNull);
      expect(authorizer.requestedScopes, isEmpty);
      await expectLater(
        connector.listContacts(),
        throwsA(isA<GoogleContactsException>()),
      );
      expect(requests, 0);

      await connector.connectReadOnly();
      expect(authorizer.requestedScopes, [
        [GoogleContactsConnector.readonlyScope],
      ]);
      expect(await connector.connectedEmail, 'himangshuraj@gmail.com');
      expect(
        await secrets.read(key: 'google_contacts_access_token'),
        'contacts-token',
      );
      expect(await secrets.read(key: 'google_calendar_access_token'), isNull);
      expect(await secrets.read(key: 'google_tasks_access_token'), isNull);
      expect(requests, 0, reason: 'Connecting must not load contacts.');
    },
  );

  test('one explicit load reads only names/email/phone and paginates at most 3 pages', () async {
    final requests = <http.Request>[];
    final connector = GoogleContactsConnector(
      storage: secrets,
      authorizer: authorizer,
      now: () => fixedNow,
      clientFactory: () => MockClient((request) async {
        requests.add(request);
        final page = requests.length;
        return http.Response(
          jsonEncode({
            'connections': [
              {
                'resourceName': 'people/$page',
                'names': [
                  {'displayName': 'Contact $page'},
                ],
                'emailAddresses': [
                  {'value': 'person$page@example.com'},
                ],
                'phoneNumbers': [
                  {'value': '+1 555 010$page'},
                ],
                'birthdays': [
                  {
                    'date': {'year': 2000},
                  },
                ],
              },
              {
                'resourceName': 'people/empty',
                'names': [],
                'emailAddresses': [],
                'phoneNumbers': [],
              },
            ],
            'nextPageToken': 'token-$page',
          }),
          200,
        );
      }),
    );
    await connector.connectReadOnly();

    final contacts = await connector.listContacts();
    expect(contacts, hasLength(3));
    expect(contacts.first.displayName, 'Contact 1');
    expect(contacts.first.emails, ['person1@example.com']);
    expect(contacts.first.phones, ['+1 555 0101']);
    expect(requests, hasLength(3));
    expect(requests.first.method, 'GET');
    expect(requests.first.url.path, '/v1/people/me/connections');
    expect(requests.first.url.queryParameters['pageSize'], '100');
    expect(
      requests.first.url.queryParameters['personFields'],
      'names,emailAddresses,phoneNumbers',
    );
    expect(requests.first.url.queryParameters['pageToken'], isNull);
    expect(requests[1].url.queryParameters['pageToken'], 'token-1');
    expect(requests[2].url.queryParameters['pageToken'], 'token-2');
    expect(requests.every((request) => request.method == 'GET'), isTrue);
    expect(requests.every((request) => request.body.isEmpty), isTrue);
    expect(
      requests.every(
        (request) =>
            request.headers['authorization'] == 'Bearer contacts-token',
      ),
      isTrue,
    );
    expect(
      requests.every(
        (request) => !request.url.queryParameters.containsKey('syncToken'),
      ),
      isTrue,
    );
  });

  test('401 clears only Contacts authorization and is never retried', () async {
    var calls = 0;
    final connector = GoogleContactsConnector(
      storage: secrets,
      authorizer: authorizer,
      now: () => fixedNow,
      clientFactory: () => MockClient((_) async {
        calls++;
        return http.Response('{}', 401);
      }),
    );
    await connector.connectReadOnly();
    await secrets.write(key: 'google_tasks_access_token', value: 'tasks-token');
    await secrets.write(
      key: 'google_calendar_access_token',
      value: 'calendar-token',
    );

    await expectLater(
      connector.listContacts(),
      throwsA(isA<GoogleContactsException>()),
    );
    expect(calls, 1);
    expect(authorizer.clearedTokens, ['contacts-token']);
    expect(await connector.connectedEmail, isNull);
    expect(await secrets.read(key: 'google_contacts_access_token'), isNull);
    expect(await secrets.read(key: 'google_tasks_access_token'), 'tasks-token');
    expect(
      await secrets.read(key: 'google_calendar_access_token'),
      'calendar-token',
    );
  });

  test('local token expiry prevents network access', () async {
    var now = fixedNow;
    var calls = 0;
    final connector = GoogleContactsConnector(
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
      connector.listContacts(),
      throwsA(isA<GoogleContactsException>()),
    );
    expect(calls, 0);
    expect(await secrets.read(key: 'google_contacts_access_token'), isNull);
  });

  test('disconnect clears only its token and account metadata', () async {
    final connector = GoogleContactsConnector(
      storage: secrets,
      authorizer: authorizer,
      now: () => fixedNow,
    );
    await connector.connectReadOnly();
    await secrets.write(key: 'google_tasks_access_token', value: 'tasks-token');
    await secrets.write(
      key: 'google_calendar_access_token',
      value: 'calendar-token',
    );
    await connector.disconnect();
    expect(authorizer.clearedTokens, ['contacts-token']);
    expect(await connector.connectedEmail, isNull);
    expect(await secrets.read(key: 'google_contacts_access_token'), isNull);
    expect(await secrets.read(key: 'google_contacts_email'), isNull);
    expect(await secrets.read(key: 'google_tasks_access_token'), 'tasks-token');
    expect(
      await secrets.read(key: 'google_calendar_access_token'),
      'calendar-token',
    );
  });
}

class _MemorySecrets implements GoogleContactsSecretStore {
  final Map<String, String> values = {};
  @override
  Future<String?> read({required String key}) async => values[key];
  @override
  Future<void> write({required String key, required String value}) async =>
      values[key] = value;
  @override
  Future<void> delete({required String key}) async => values.remove(key);
}

class _FakeAuthorizer implements GoogleContactsAuthorizer {
  final requestedScopes = <List<String>>[];
  final clearedTokens = <String>[];
  @override
  Future<GoogleContactsCredentials> authorize(List<String> scopes) async {
    requestedScopes.add(List<String>.from(scopes));
    return const GoogleContactsCredentials(
      email: 'himangshuraj@gmail.com',
      accessToken: 'contacts-token',
    );
  }

  @override
  Future<void> clearAuthorizationToken(String accessToken) async {
    clearedTokens.add(accessToken);
  }
}
