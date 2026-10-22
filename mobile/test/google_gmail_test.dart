import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_assistant/google_gmail.dart';

void main() {
  final fixedNow = DateTime.utc(2026, 10, 22, 8);
  late _MemorySecrets secrets;
  late _FakeAuthorizer authorizer;

  setUp(() {
    secrets = _MemorySecrets();
    authorizer = _FakeAuthorizer();
  });

  test(
    'missing OAuth configuration fails closed before account or API access',
    () async {
      var apiCalls = 0;
      final connector = GoogleGmailConnector(
        storage: secrets,
        authorizer: GoogleGmailGoogleSignInAuthorizer(serverClientId: ''),
        now: () => fixedNow,
        clientFactory: () => MockClient((_) async {
          apiCalls++;
          return http.Response('{}', 200);
        }),
      );

      await expectLater(
        connector.connectReadOnly(),
        throwsA(
          isA<GoogleGmailException>().having(
            (error) => error.message,
            'message',
            contains('not configured'),
          ),
        ),
      );
      expect(await connector.connectedEmail, isNull);
      expect(apiCalls, 0);
    },
  );

  test(
    'connect requests only Gmail read-only and does not read mail',
    () async {
      var apiCalls = 0;
      final connector = GoogleGmailConnector(
        storage: secrets,
        authorizer: authorizer,
        now: () => fixedNow,
        clientFactory: () => MockClient((_) async {
          apiCalls++;
          return http.Response('{}', 200);
        }),
      );

      await expectLater(
        connector.loadRecentInbox(),
        throwsA(isA<GoogleGmailException>()),
      );
      await connector.connectReadOnly();

      expect(authorizer.requestedScopes, [
        [GoogleGmailConnector.readonlyScope],
      ]);
      expect(await connector.connectedEmail, 'himangshuraj@gmail.com');
      expect(
        await secrets.read(key: 'google_gmail_access_token'),
        'gmail-token',
      );
      expect(await secrets.read(key: 'google_tasks_access_token'), isNull);
      expect(apiCalls, 0, reason: 'Sign-in must not fetch mail.');
    },
  );

  test(
    'explicit inbox load fetches at most ten headers and no bodies',
    () async {
      final requests = <http.Request>[];
      final connector = GoogleGmailConnector(
        storage: secrets,
        authorizer: authorizer,
        now: () => fixedNow,
        clientFactory: () => MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/messages')) {
            return http.Response(
              jsonEncode({
                'messages': [
                  {'id': 'msg-1', 'threadId': 'thread-1'},
                  {'id': 'msg-2', 'threadId': 'thread-2'},
                ],
              }),
              200,
            );
          }
          final id = request.url.path.split('/').last;
          return http.Response(
            jsonEncode({
              'id': id,
              'threadId': 'thread-$id',
              'payload': {
                'headers': [
                  {'name': 'From', 'value': '$id@example.com'},
                  {'name': 'Subject', 'value': 'Subject $id'},
                  {'name': 'Date', 'value': 'Thu, 22 Oct 2026 08:00:00 +0000'},
                ],
              },
            }),
            200,
          );
        }),
      );
      await connector.connectReadOnly();
      expect(requests, isEmpty);

      final messages = await connector.loadRecentInbox();

      expect(messages, hasLength(2));
      expect(messages.first.subject, 'Subject msg-1');
      expect(requests.map((request) => request.method), everyElement('GET'));
      expect(
        requests.first.url.queryParameters['q'],
        'in:inbox -in:spam -in:trash',
      );
      expect(requests.first.url.queryParameters['maxResults'], '10');
      expect(
        requests.first.url.queryParameters['fields'],
        'messages(id,threadId)',
      );
      for (final request in requests.skip(1)) {
        expect(request.url.queryParameters['format'], 'metadata');
        expect(request.url.queryParametersAll['metadataHeaders'], [
          'From',
          'Subject',
          'Date',
        ]);
        expect(
          request.url.queryParameters['fields'],
          'id,threadId,payload(headers)',
        );
      }
    },
  );

  test(
    'message body is fetched only after selecting a listed id, with GET only',
    () async {
      final requests = <http.Request>[];
      final plainText = 'A private message body.\nOnly shown after selection.';
      final encoded = base64Url
          .encode(utf8.encode(plainText))
          .replaceAll('=', '');
      final connector = GoogleGmailConnector(
        storage: secrets,
        authorizer: authorizer,
        now: () => fixedNow,
        clientFactory: () => MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/messages')) {
            return http.Response(
              jsonEncode({
                'messages': [
                  {'id': 'selected'},
                ],
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/selected') &&
              request.url.queryParameters['format'] == 'full') {
            return http.Response(
              jsonEncode({
                'id': 'selected',
                'payload': {
                  'mimeType': 'multipart/mixed',
                  'parts': [
                    {
                      'mimeType': 'text/plain',
                      'body': {'data': encoded},
                    },
                    {
                      'mimeType': 'application/pdf',
                      'filename': 'attachment.pdf',
                      'body': {'attachmentId': 'never-fetched'},
                    },
                  ],
                },
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'id': 'selected',
              'payload': {'headers': []},
            }),
            200,
          );
        }),
      );
      await connector.connectReadOnly();

      await expectLater(
        connector.readSelectedMessage('not-listed'),
        throwsA(isA<GoogleGmailException>()),
      );
      expect(requests, isEmpty);

      await connector.loadRecentInbox();
      expect(requests, hasLength(2));
      expect(requests.every((request) => request.method == 'GET'), isTrue);
      final body = await connector.readSelectedMessage('selected');

      expect(body.text, plainText);
      expect(body.isPlainText, isTrue);
      expect(requests, hasLength(3));
      expect(requests.last.method, 'GET');
      expect(requests.last.url.queryParameters['format'], 'full');
      expect(requests.last.url.queryParameters['fields'], 'id,payload');
      expect(
        requests.any((request) => request.url.path.contains('attachments')),
        isFalse,
      );
      expect(secrets.values.values, isNot(contains(plainText)));
    },
  );

  test(
    'does not fetch message attachment bodies or mislabel html as plain text',
    () async {
      final requests = <http.Request>[];
      final html = base64Url
          .encode(utf8.encode('<p>html only</p>'))
          .replaceAll('=', '');
      final connector = GoogleGmailConnector(
        storage: secrets,
        authorizer: authorizer,
        now: () => fixedNow,
        clientFactory: () => MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/messages')) {
            return http.Response(
              jsonEncode({
                'messages': [
                  {'id': 'html-msg'},
                ],
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/html-msg') &&
              request.url.queryParameters['format'] == 'full') {
            return http.Response(
              jsonEncode({
                'payload': {
                  'mimeType': 'multipart/mixed',
                  'parts': [
                    {
                      'mimeType': 'text/html',
                      'body': {'data': html},
                    },
                    {
                      'mimeType': 'text/plain',
                      'filename': 'note.txt',
                      'body': {'data': html},
                    },
                  ],
                },
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'id': 'html-msg',
              'payload': {'headers': []},
            }),
            200,
          );
        }),
      );
      await connector.connectReadOnly();
      await connector.loadRecentInbox();

      final body = await connector.readSelectedMessage('html-msg');

      expect(body.isPlainText, isFalse);
      expect(body.text, contains('no inline plain-text body'));
    },
  );

  test('disconnect clears only Gmail credentials and transient ids', () async {
    final requests = <http.Request>[];
    final connector = GoogleGmailConnector(
      storage: secrets,
      authorizer: authorizer,
      now: () => fixedNow,
      clientFactory: () => MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'messages': [
              {'id': 'one'},
            ],
          }),
          200,
        );
      }),
    );
    await connector.connectReadOnly();
    await connector.loadRecentInbox();
    secrets.values['google_tasks_access_token'] = 'keep-other-service';

    await connector.disconnect();

    expect(await connector.connectedEmail, isNull);
    expect(await secrets.read(key: 'google_gmail_access_token'), isNull);
    expect(await secrets.read(key: 'google_gmail_token_saved_at'), isNull);
    expect(await secrets.read(key: 'google_gmail_email'), isNull);
    expect(
      await secrets.read(key: 'google_tasks_access_token'),
      'keep-other-service',
    );
    expect(authorizer.clearedTokens, ['gmail-token']);
    await expectLater(
      connector.readSelectedMessage('one'),
      throwsA(isA<GoogleGmailException>()),
    );
  });

  test(
    'expired token blocks requests and clears Gmail-only credentials',
    () async {
      var now = fixedNow;
      var apiCalls = 0;
      final connector = GoogleGmailConnector(
        storage: secrets,
        authorizer: authorizer,
        now: () => now,
        clientFactory: () => MockClient((_) async {
          apiCalls++;
          return http.Response('{}', 200);
        }),
      );
      await connector.connectReadOnly();
      now = fixedNow.add(const Duration(minutes: 56));

      await expectLater(
        connector.loadRecentInbox(),
        throwsA(
          isA<GoogleGmailException>().having(
            (error) => error.message,
            'message',
            contains('expired'),
          ),
        ),
      );
      expect(apiCalls, 0);
      expect(await connector.connectedEmail, isNull);
    },
  );

  test('401 clears local authorization and never retries', () async {
    var calls = 0;
    final connector = GoogleGmailConnector(
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
      connector.loadRecentInbox(),
      throwsA(
        isA<GoogleGmailException>().having(
          (error) => error.message,
          'message',
          contains('no request was retried'),
        ),
      ),
    );
    expect(calls, 1);
    expect(await connector.connectedEmail, isNull);
    expect(authorizer.clearedTokens, ['gmail-token']);
  });

  test('non-GET write access is not exposed by the connector', () async {
    final methods = <String>[];
    final connector = GoogleGmailConnector(
      storage: secrets,
      authorizer: authorizer,
      now: () => fixedNow,
      clientFactory: () => MockClient((request) async {
        methods.add(request.method);
        return http.Response(jsonEncode({'messages': []}), 200);
      }),
    );
    await connector.connectReadOnly();
    await connector.loadRecentInbox();

    expect(methods, everyElement('GET'));
    expect(
      GoogleGmailConnector.readonlyScope,
      'https://www.googleapis.com/auth/gmail.readonly',
    );
  });
}

class _MemorySecrets implements GoogleGmailSecretStore {
  final Map<String, String> values = {};
  @override
  Future<String?> read({required String key}) async => values[key];
  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }
}

class _FakeAuthorizer implements GoogleGmailAuthorizer {
  final List<List<String>> requestedScopes = [];
  final List<String> clearedTokens = [];
  @override
  Future<GoogleGmailCredentials> authorize(List<String> scopes) async {
    requestedScopes.add(List.of(scopes));
    return const GoogleGmailCredentials(
      email: 'himangshuraj@gmail.com',
      accessToken: 'gmail-token',
    );
  }

  @override
  Future<void> clearAuthorizationToken(String accessToken) async {
    clearedTokens.add(accessToken);
  }
}
