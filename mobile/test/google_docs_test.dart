import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_assistant/google_docs.dart';
import 'package:personal_assistant/google_drive.dart';

void main() {
  final fixedNow = DateTime.utc(2026, 10, 22, 8);
  late _MemorySecrets secrets;
  late _FakeAuthorizer authorizer;

  setUp(() {
    secrets = _MemorySecrets();
    authorizer = _FakeAuthorizer();
  });

  test(
    'Google Docs uses only the shared non-sensitive drive.file scope',
    () async {
      var requests = 0;
      final connector = GoogleDocsConnector(
        storage: secrets,
        authorizer: authorizer,
        now: () => fixedNow,
        clientFactory: () => MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );

      await connector.connect();

      expect(GoogleDocsConnector.fileScope, GoogleDriveConnector.fileScope);
      expect(authorizer.requestedScopes, [
        ['https://www.googleapis.com/auth/drive.file'],
      ]);
      expect(
        await secrets.read(key: 'google_docs_access_token'),
        'shared-token',
      );
      expect(await secrets.read(key: 'google_drive_access_token'), isNull);
      expect(requests, 0, reason: 'Connect does not enumerate or read files.');
    },
  );

  test('missing OAuth setup fails closed without saving credentials', () async {
    final connector = GoogleDocsConnector(
      storage: secrets,
      authorizer: GoogleDocsGoogleSignInAuthorizer(serverClientId: ''),
      now: () => fixedNow,
    );

    await expectLater(
      connector.connect(),
      throwsA(
        isA<GoogleDocsException>().having(
          (error) => error.message,
          'message',
          contains('not configured'),
        ),
      ),
    );
    expect(await connector.connectedEmail, isNull);
    expect(await secrets.read(key: 'google_docs_access_token'), isNull);
  });

  test(
    'lists only app-tagged Docs and fetches only a selected document',
    () async {
      final requests = <http.Request>[];
      final connector = GoogleDocsConnector(
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
                    'id': 'doc-1',
                    'name': 'Study plan',
                    'mimeType': GoogleDocsConnector.documentMimeType,
                    'modifiedTime': '2026-10-22T07:00:00Z',
                  },
                ],
              }),
              200,
            );
          }
          if (request.url.path == '/v1/documents/doc-1') {
            return http.Response(
              jsonEncode({
                'documentId': 'doc-1',
                'title': 'Study plan',
                'body': {
                  'content': [
                    {
                      'startIndex': 1,
                      'endIndex': 14,
                      'paragraph': {
                        'elements': [
                          {
                            'textRun': {'content': 'Read chapter\n'},
                          },
                        ],
                      },
                    },
                  ],
                },
              }),
              200,
            );
          }
          return http.Response('unexpected', 404);
        }),
      );
      await connector.connect();

      final docs = await connector.listCreatedDocuments();
      expect(docs.single.title, 'Study plan');
      expect(requests.single.url.host, 'www.googleapis.com');
      expect(requests.single.url.path, '/drive/v3/files');
      expect(requests.single.url.queryParameters['pageSize'], '25');
      expect(
        requests.single.url.queryParameters['q'],
        contains("mimeType = '${GoogleDocsConnector.documentMimeType}'"),
      );
      expect(
        requests.single.url.queryParameters['q'],
        contains(
          "appProperties has { key='personalAssistantDoc' and value='1' }",
        ),
      );
      expect(
        requests.single.url.queryParameters['q'],
        contains('trashed = false'),
      );

      await expectLater(
        connector.readSelectedDocument('not-selected'),
        throwsA(isA<GoogleDocsException>()),
      );
      expect(requests, hasLength(1), reason: 'Unselected IDs make no request.');
      final content = await connector.readSelectedDocument(docs.single.id);
      expect(content.title, 'Study plan');
      expect(content.text, 'Read chapter\n');
      expect(content.endIndex, 14);
      expect(requests.last.url.host, 'docs.googleapis.com');
      expect(requests.last.headers['authorization'], 'Bearer shared-token');
    },
  );

  test(
    'creates a tagged Google Doc by supported text conversion in one request',
    () async {
      final requests = <http.Request>[];
      final connector = GoogleDocsConnector(
        storage: secrets,
        authorizer: authorizer,
        now: () => fixedNow,
        clientFactory: () => MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({
              'id': 'doc-new',
              'name': 'Linear equations',
              'mimeType': GoogleDocsConnector.documentMimeType,
            }),
            200,
          );
        }),
      );
      await connector.connect();

      final doc = await connector.createDocument(
        title: ' Linear equations ',
        text: 'Solve for x: 2x + 3 = 9',
      );
      expect(doc.id, 'doc-new');
      expect(doc.title, 'Linear equations');
      expect(requests, hasLength(1));
      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.host, 'www.googleapis.com');
      expect(request.url.path, '/upload/drive/v3/files');
      expect(request.url.queryParameters['uploadType'], 'multipart');
      final payload = utf8.decode(request.bodyBytes);
      expect(
        payload,
        contains('"mimeType":"${GoogleDocsConnector.documentMimeType}"'),
      );
      expect(payload, contains('"personalAssistantDoc":"1"'));
      expect(payload, contains('Solve for x: 2x + 3 = 9'));
      expect(request.headers['authorization'], 'Bearer shared-token');
      // The returned ID becomes selectable without searching arbitrary files.
      expect((await connector.readSelectedDocument('doc-new')).id, 'doc-new');
    },
  );

  test(
    'edits only a selected document after a fresh read and explicit call',
    () async {
      final requests = <http.Request>[];
      final connector = GoogleDocsConnector(
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
                    'id': 'doc-edit',
                    'name': 'Draft',
                    'mimeType': GoogleDocsConnector.documentMimeType,
                  },
                ],
              }),
              200,
            );
          }
          if (request.url.path == '/v1/documents/doc-edit') {
            return http.Response(
              jsonEncode({
                'documentId': 'doc-edit',
                'title': 'Draft',
                'body': {
                  'content': [
                    {
                      'startIndex': 1,
                      'endIndex': 7,
                      'paragraph': {
                        'elements': [
                          {
                            'textRun': {'content': 'old\n'},
                          },
                        ],
                      },
                    },
                  ],
                },
              }),
              200,
            );
          }
          if (request.url.path == '/v1/documents/doc-edit:batchUpdate') {
            return http.Response(jsonEncode({'documentId': 'doc-edit'}), 200);
          }
          return http.Response('unexpected', 404);
        }),
      );
      await connector.connect();
      await connector.listCreatedDocuments();
      expect(
        requests,
        hasLength(1),
        reason: 'Listing alone does not read content.',
      );

      await connector.replaceSelectedDocumentText(
        documentId: 'doc-edit',
        text: 'new notes\nline two',
      );
      expect(requests.map((request) => request.method), ['GET', 'GET', 'POST']);
      expect(requests.last.url.host, 'docs.googleapis.com');
      final body = jsonDecode(requests.last.body) as Map<String, dynamic>;
      final operations = body['requests'] as List;
      expect(operations[0]['deleteContentRange']['range'], {
        'startIndex': 1,
        'endIndex': 6,
      });
      expect(operations[1]['insertText']['location'], {'index': 1});
      expect(operations[1]['insertText']['text'], 'new notes\nline two');
    },
  );

  test(
    'rejects unsafe, overlong, empty, and unselected edits before network',
    () async {
      var requests = 0;
      final connector = GoogleDocsConnector(
        storage: secrets,
        authorizer: authorizer,
        now: () => fixedNow,
        clientFactory: () => MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );
      await connector.connect();
      await expectLater(
        connector.createDocument(title: ' ', text: 'hello'),
        throwsA(isA<GoogleDocsException>()),
      );
      await expectLater(
        connector.createDocument(
          title: 'Big',
          text: 'x' * (GoogleDocsConnector.maxTextBytes + 1),
        ),
        throwsA(isA<GoogleDocsException>()),
      );
      await expectLater(
        connector.replaceSelectedDocumentText(
          documentId: 'arbitrary',
          text: 'text',
        ),
        throwsA(isA<GoogleDocsException>()),
      );
      expect(requests, 0);
    },
  );

  test('Docs disconnect removes only its local credentials and preserves Drive token', () async {
    final connector = GoogleDocsConnector(
      storage: secrets,
      authorizer: authorizer,
      now: () => fixedNow,
    );
    await connector.connect();
    await secrets.write(
      key: 'google_drive_access_token',
      value: 'same-scope-drive-copy',
    );
    await secrets.write(
      key: 'google_drive_email',
      value: 'himangshuraj@gmail.com',
    );

    await connector.disconnect();

    expect(await connector.connectedEmail, isNull);
    expect(await secrets.read(key: 'google_docs_access_token'), isNull);
    expect(
      await secrets.read(key: 'google_drive_access_token'),
      'same-scope-drive-copy',
    );
    expect(
      await secrets.read(key: 'google_drive_email'),
      'himangshuraj@gmail.com',
    );
    expect(authorizer.requestedScopes.single, [GoogleDocsConnector.fileScope]);
  });

  test(
    'expired token is cleared before any request; 401 is never retried',
    () async {
      var now = fixedNow;
      var calls = 0;
      final connector = GoogleDocsConnector(
        storage: secrets,
        authorizer: authorizer,
        now: () => now,
        clientFactory: () => MockClient((_) async {
          calls++;
          return http.Response('{}', 401);
        }),
      );
      await connector.connect();
      await expectLater(
        connector.listCreatedDocuments(),
        throwsA(isA<GoogleDocsException>()),
      );
      expect(calls, 1);
      expect(await connector.connectedEmail, isNull);
      await expectLater(
        connector.listCreatedDocuments(),
        throwsA(isA<GoogleDocsException>()),
      );
      expect(calls, 1);

      await connector.connect();
      now = fixedNow.add(const Duration(minutes: 55));
      await expectLater(
        connector.listCreatedDocuments(),
        throwsA(isA<GoogleDocsException>()),
      );
      expect(calls, 1);
      expect(await connector.connectedEmail, isNull);
    },
  );
}

class _MemorySecrets implements GoogleDocsSecretStore {
  final values = <String, String>{};
  @override
  Future<String?> read({required String key}) async => values[key];
  @override
  Future<void> write({required String key, required String value}) async =>
      values[key] = value;
  @override
  Future<void> delete({required String key}) async => values.remove(key);
}

class _FakeAuthorizer implements GoogleDocsAuthorizer {
  final requestedScopes = <List<String>>[];
  @override
  Future<GoogleDocsCredentials> authorize(List<String> scopes) async {
    requestedScopes.add(List<String>.from(scopes));
    return const GoogleDocsCredentials(
      email: 'himangshuraj@gmail.com',
      accessToken: 'shared-token',
    );
  }
}
