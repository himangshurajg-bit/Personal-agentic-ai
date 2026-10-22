import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_assistant/google_sheets.dart';

void main() {
  final fixedNow = DateTime.utc(2026, 10, 22, 8);
  late _MemorySecrets secrets;
  late _FakeAuthorizer authorizer;

  setUp(() {
    secrets = _MemorySecrets();
    authorizer = _FakeAuthorizer();
  });

  test('connect requests only drive.file and does not access Sheets', () async {
    var calls = 0;
    final connector = GoogleSheetsConnector(
      storage: secrets,
      authorizer: authorizer,
      now: () => fixedNow,
      clientFactory: () => MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );

    expect(await connector.connectedEmail, isNull);
    await connector.connect();
    expect(authorizer.requestedScopes, [
      [GoogleSheetsConnector.fileScope],
    ]);
    expect(await connector.connectedEmail, 'owner@example.test');
    expect(
      await secrets.read(key: 'google_sheets_access_token'),
      'sheet-token',
    );
    expect(calls, 0, reason: 'Sign-in alone must not access remote files.');
  });

  test(
    'only app-tagged Sheets are listed and an explicit selection can be opened',
    () async {
      final requests = <http.Request>[];
      final connector = GoogleSheetsConnector(
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
                    'id': 'sheet-1',
                    'name': 'Study plan',
                    'mimeType': GoogleSheetsConnector.spreadsheetMimeType,
                    'modifiedTime': '2026-10-22T07:00:00Z',
                  },
                ],
              }),
              200,
            );
          }
          if (request.url.path == '/v4/spreadsheets/sheet-1') {
            return http.Response(
              jsonEncode({
                'spreadsheetId': 'sheet-1',
                'properties': {'title': 'Study plan'},
                'sheets': [
                  {
                    'properties': {
                      'sheetId': 0,
                      'title': 'Notes',
                      'gridProperties': {'rowCount': 20, 'columnCount': 5},
                    },
                  },
                ],
              }),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      );
      await connector.connect();

      final files = await connector.listCreatedSpreadsheets();
      expect(files.single.title, 'Study plan');
      expect(requests.single.method, 'GET');
      expect(
        requests.single.url.queryParameters['q'],
        contains('appProperties has'),
      );
      expect(
        requests.single.url.queryParameters['q'],
        contains('trashed = false'),
      );
      expect(requests.single.url.queryParameters['pageSize'], '25');

      await expectLater(
        connector.openSelectedSpreadsheet('arbitrary-id'),
        throwsA(isA<GoogleSheetsException>()),
      );
      expect(
        requests,
        hasLength(1),
        reason: 'Unselected IDs must not cause API calls.',
      );

      final selected = await connector.openSelectedSpreadsheet(files.single.id);
      expect(selected.tabs.single.title, 'Notes');
      expect(requests.last.url.queryParameters['includeGridData'], 'false');
      expect(requests.last.headers['authorization'], 'Bearer sheet-token');
    },
  );

  test(
    'create, read, and write are explicit and writes use RAW bounded values',
    () async {
      final requests = <http.Request>[];
      final connector = GoogleSheetsConnector(
        storage: secrets,
        authorizer: authorizer,
        now: () => fixedNow,
        clientFactory: () => MockClient((request) async {
          requests.add(request);
          if (request.method == 'POST' &&
              request.url.path == '/v4/spreadsheets') {
            return http.Response(
              jsonEncode({
                'spreadsheetId': 'sheet-created',
                'properties': {'title': "O'Brien study"},
                'sheets': [
                  {
                    'properties': {
                      'sheetId': 0,
                      'title': "Teacher's notes",
                      'gridProperties': {'rowCount': 50, 'columnCount': 10},
                    },
                  },
                ],
              }),
              200,
            );
          }
          if (request.method == 'PATCH' &&
              request.url.path == '/drive/v3/files/sheet-created') {
            return http.Response('{}', 200);
          }
          if (request.method == 'GET' &&
              request.url.path.contains('/values/')) {
            return http.Response(
              jsonEncode({
                'values': [
                  ['=1+1', 'two'],
                  ['3', 'four'],
                ],
              }),
              200,
            );
          }
          if (request.method == 'PUT' &&
              request.url.path.contains('/values/')) {
            return http.Response(jsonEncode({'updatedCells': 4}), 200);
          }
          return http.Response('{}', 404);
        }),
      );
      await connector.connect();

      final created = await connector.createSpreadsheet('  O\'Brien study  ');
      expect(created.id, 'sheet-created');
      expect(requests[0].method, 'POST');
      expect(
        jsonDecode(requests[0].body)['properties']['title'],
        "O'Brien study",
      );
      expect(requests[1].method, 'PATCH');
      expect(jsonDecode(requests[1].body)['appProperties'], {
        'personalAssistantSheet': '1',
      });

      final range = await connector.readRange(
        spreadsheetId: created.id,
        sheetTitle: "Teacher's notes",
        range: 'A1:B2',
      );
      expect(range.rows, [
        ['=1+1', 'two'],
        ['3', 'four'],
      ]);
      expect(requests[2].method, 'GET');
      expect(
        requests[2].url.queryParameters['valueRenderOption'],
        'FORMATTED_VALUE',
      );
      expect(requests[2].url.path, contains('Teacher'));

      await connector.writeRange(
        spreadsheetId: created.id,
        sheetTitle: "Teacher's notes",
        range: 'A1:B2',
        tabSeparatedValues: '=1+1\ttwo\n3\tfour',
      );
      expect(requests[3].method, 'PUT');
      expect(requests[3].url.queryParameters['valueInputOption'], 'RAW');
      expect(requests[3].headers['authorization'], 'Bearer sheet-token');
      expect(jsonDecode(requests[3].body), {
        'majorDimension': 'ROWS',
        'values': [
          ['=1+1', 'two'],
          ['3', 'four'],
        ],
      });
    },
  );

  test(
    'invalid ranges and mismatched cell data make no network request',
    () async {
      var calls = 0;
      final connector = GoogleSheetsConnector(
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
        connector.createSpreadsheet('   '),
        throwsA(isA<GoogleSheetsException>()),
      );
      await expectLater(
        connector.createSpreadsheet('x' * 121),
        throwsA(isA<GoogleSheetsException>()),
      );
      expect(calls, 0);

      await expectLater(
        connector.readRange(
          spreadsheetId: 'not-selected',
          sheetTitle: 'Sheet1',
          range: 'A1',
        ),
        throwsA(isA<GoogleSheetsException>()),
      );
      expect(calls, 0);
    },
  );

  test('rejects an API response larger than the selected range', () async {
    final connector = GoogleSheetsConnector(
      storage: secrets,
      authorizer: authorizer,
      now: () => fixedNow,
      clientFactory: () => MockClient((request) async {
        if (request.url.path == '/drive/v3/files') {
          return http.Response(
            jsonEncode({
              'files': [
                {
                  'id': 'sheet-1',
                  'name': 'Bounded',
                  'mimeType': GoogleSheetsConnector.spreadsheetMimeType,
                },
              ],
            }),
            200,
          );
        }
        if (request.url.path == '/v4/spreadsheets/sheet-1') {
          return http.Response(
            jsonEncode({
              'spreadsheetId': 'sheet-1',
              'properties': {'title': 'Bounded'},
              'sheets': [
                {
                  'properties': {'sheetId': 0, 'title': 'One tab'},
                },
              ],
            }),
            200,
          );
        }
        if (request.url.path.contains('/values/')) {
          return http.Response(
            jsonEncode({
              'values': [
                ['one', 'two'],
              ],
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      }),
    );
    await connector.connect();
    final file = (await connector.listCreatedSpreadsheets()).single;
    await connector.openSelectedSpreadsheet(file.id);

    await expectLater(
      connector.readRange(
        spreadsheetId: file.id,
        sheetTitle: 'One tab',
        range: 'A1:A1',
      ),
      throwsA(isA<GoogleSheetsException>()),
    );
  });

  test('401 clears credentials without retry and expired tokens fail before network access', () async {
    var calls = 0;
    var now = fixedNow;
    final connector = GoogleSheetsConnector(
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
      connector.listCreatedSpreadsheets(),
      throwsA(isA<GoogleSheetsException>()),
    );
    expect(calls, 1);
    expect(await connector.connectedEmail, isNull);
    expect(await secrets.read(key: 'google_sheets_access_token'), isNull);

    await connector.connect();
    now = fixedNow.add(const Duration(minutes: 56));
    await expectLater(
      connector.listCreatedSpreadsheets(),
      throwsA(isA<GoogleSheetsException>()),
    );
    expect(calls, 1);
    expect(await connector.connectedEmail, isNull);
  });
}

class _MemorySecrets implements GoogleSheetsSecretStore {
  final values = <String, String>{};

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async =>
      values[key] = value;

  @override
  Future<void> delete({required String key}) async => values.remove(key);
}

class _FakeAuthorizer implements GoogleSheetsAuthorizer {
  final requestedScopes = <List<String>>[];

  @override
  Future<GoogleSheetsCredentials> authorize(List<String> scopes) async {
    requestedScopes.add(List<String>.from(scopes));
    return const GoogleSheetsCredentials(
      email: 'owner@example.test',
      accessToken: 'sheet-token',
    );
  }
}
