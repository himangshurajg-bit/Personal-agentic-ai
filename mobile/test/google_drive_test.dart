import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_assistant/google_drive.dart';

void main() {
  final fixedNow = DateTime.utc(2026, 10, 22, 8);
  late _MemorySecrets secrets;
  late _FakeAuthorizer authorizer;

  setUp(() {
    secrets = _MemorySecrets();
    authorizer = _FakeAuthorizer();
  });

  test('missing OAuth configuration fails closed', () async {
    final connector = GoogleDriveConnector(
      storage: secrets,
      authorizer: GoogleDriveGoogleSignInAuthorizer(serverClientId: ''),
      now: () => fixedNow,
    );

    await expectLater(
      connector.connect(),
      throwsA(
        isA<GoogleDriveException>().having(
          (e) => e.message,
          'message',
          contains('not configured'),
        ),
      ),
    );
    expect(await connector.connectedEmail, isNull);
    expect(await secrets.read(key: 'google_drive_access_token'), isNull);
  });

  test('connection requests only drive.file and does not enumerate or access files', () async {
    var requests = 0;
    final connector = GoogleDriveConnector(
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
    await connector.connect();
    expect(authorizer.requestedScopes, [
      [GoogleDriveConnector.fileScope],
    ]);
    expect(await connector.connectedEmail, 'himangshuraj@gmail.com');
    expect(await secrets.read(key: 'google_drive_access_token'), 'drive-token');
    expect(
      requests,
      0,
      reason: 'OAuth alone must not read or write Drive files.',
    );
  });

  test(
    'only app-tagged files are listed and selected rows can be read explicitly',
    () async {
      final requests = <http.Request>[];
      final connector = GoogleDriveConnector(
        storage: secrets,
        authorizer: authorizer,
        now: () => fixedNow,
        clientFactory: () => MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/drive/v3/files') {
            return http.Response(
              jsonEncode({
                'files': [
                  {
                    'id': 'owned-1',
                    'name': 'My notes.txt',
                    'mimeType': 'text/plain',
                    'modifiedTime': '2026-10-22T07:00:00Z',
                  },
                ],
              }),
              200,
            );
          }
          if (request.url.path == '/drive/v3/files/owned-1') {
            return http.Response(
              'private note text',
              200,
              headers: {'content-type': 'text/plain'},
            );
          }
          return http.Response('unexpected', 404);
        }),
      );
      await connector.connect();

      final files = await connector.listAppFiles();
      expect(files, hasLength(1));
      expect(files.single.name, 'My notes.txt');
      expect(requests.first.method, 'GET');
      expect(
        requests.first.url.queryParameters['q'],
        contains(
          "appProperties has { key='personalAssistantFile' and value='1' }",
        ),
      );
      expect(
        requests.first.url.queryParameters['q'],
        contains('trashed = false'),
      );
      expect(requests.first.url.queryParameters['pageSize'], '25');

      await expectLater(
        connector.readSelectedTextFile('arbitrary-id'),
        throwsA(isA<GoogleDriveException>()),
      );
      expect(
        requests,
        hasLength(1),
        reason: 'An unselected file ID must not trigger a request.',
      );
      expect(
        await connector.readSelectedTextFile(files.single.id),
        'private note text',
      );
      expect(requests.last.method, 'GET');
      expect(requests.last.url.queryParameters['alt'], 'media');
      expect(requests.last.headers['authorization'], 'Bearer drive-token');
    },
  );

  test('text creation uses drive.file multipart metadata and returns selectable file', () async {
    final requests = <http.Request>[];
    final connector = GoogleDriveConnector(
      storage: secrets,
      authorizer: authorizer,
      now: () => fixedNow,
      clientFactory: () => MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'id': 'new-file-1',
            'name': 'Study notes.txt',
            'mimeType': 'text/plain',
            'modifiedTime': '2026-10-22T08:00:00Z',
          }),
          200,
        );
      }),
    );
    await connector.connect();

    final file = await connector.createTextFile(
      name: ' Study notes.txt ',
      contents: 'algebra\nlinear equations',
    );
    expect(file.id, 'new-file-1');
    expect(file.name, 'Study notes.txt');
    expect(requests.single.method, 'POST');
    expect(requests.single.url.path, '/upload/drive/v3/files');
    expect(requests.single.url.queryParameters['uploadType'], 'multipart');
    final payload = utf8.decode(requests.single.bodyBytes);
    expect(payload, contains('algebra\nlinear equations'));
    expect(payload, contains('"personalAssistantFile":"1"'));
    expect(payload, contains('"mimeType":"text/plain"'));
    expect(requests.single.headers['authorization'], 'Bearer drive-token');
    expect(await connector.readSelectedTextFile(file.id), isNotEmpty);
  });

  test('invalid or oversized file submissions make no request', () async {
    var calls = 0;
    final connector = GoogleDriveConnector(
      storage: secrets,
      authorizer: authorizer,
      now: () => fixedNow,
      clientFactory: () => MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    await connector.connect();

    await expectLater(
      connector.createTextFile(name: '   ', contents: 'text'),
      throwsA(isA<GoogleDriveException>()),
    );
    await expectLater(
      connector.createTextFile(
        name: 'large.txt',
        contents: 'x' * (GoogleDriveConnector.maxTextBytes + 1),
      ),
      throwsA(isA<GoogleDriveException>()),
    );
    expect(calls, 0);
  });

  test('disconnect clears only Drive credentials', () async {
    final connector = GoogleDriveConnector(
      storage: secrets,
      authorizer: authorizer,
      now: () => fixedNow,
    );
    await connector.connect();
    await secrets.write(
      key: 'google_calendar_access_token',
      value: 'calendar-token',
    );

    await connector.disconnect();

    expect(authorizer.clearedTokens, ['drive-token']);
    expect(await connector.connectedEmail, isNull);
    expect(await secrets.read(key: 'google_drive_access_token'), isNull);
    expect(
      await secrets.read(key: 'google_calendar_access_token'),
      'calendar-token',
    );
  });

  test('401 clears Drive token and never retries', () async {
    var calls = 0;
    final connector = GoogleDriveConnector(
      storage: secrets,
      authorizer: authorizer,
      now: () => fixedNow,
      clientFactory: () => MockClient((_) async {
        calls++;
        return http.Response('{}', 401);
      }),
    );
    await connector.connect();

    await expectLater(
      connector.listAppFiles(),
      throwsA(isA<GoogleDriveException>()),
    );
    expect(calls, 1);
    expect(authorizer.clearedTokens, ['drive-token']);
    expect(await connector.connectedEmail, isNull);
    await expectLater(
      connector.listAppFiles(),
      throwsA(isA<GoogleDriveException>()),
    );
    expect(calls, 1);
  });

  test('expired access token is cleared before network access', () async {
    var now = fixedNow;
    var calls = 0;
    final connector = GoogleDriveConnector(
      storage: secrets,
      authorizer: authorizer,
      now: () => now,
      clientFactory: () => MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    await connector.connect();
    now = fixedNow.add(const Duration(minutes: 56));

    expect(await connector.connectedEmail, isNull);
    await expectLater(
      connector.listAppFiles(),
      throwsA(isA<GoogleDriveException>()),
    );
    expect(calls, 0);
    expect(await secrets.read(key: 'google_drive_access_token'), isNull);
  });
}

class _MemorySecrets implements GoogleDriveSecretStore {
  final values = <String, String>{};
  @override
  Future<String?> read({required String key}) async => values[key];
  @override
  Future<void> write({required String key, required String value}) async =>
      values[key] = value;
  @override
  Future<void> delete({required String key}) async => values.remove(key);
}

class _FakeAuthorizer implements GoogleDriveAuthorizer {
  final requestedScopes = <List<String>>[];
  final clearedTokens = <String>[];

  @override
  Future<GoogleDriveCredentials> authorize(List<String> scopes) async {
    requestedScopes.add(List<String>.from(scopes));
    return const GoogleDriveCredentials(
      email: 'himangshuraj@gmail.com',
      accessToken: 'drive-token',
    );
  }

  @override
  Future<void> clearAuthorizationToken(String accessToken) async =>
      clearedTokens.add(accessToken);
}
