import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_assistant/google_tasks.dart';

void main() {
  final fixedNow = DateTime.utc(2026, 10, 22, 7);
  late _MemorySecrets secrets;
  late _FakeAuthorizer authorizer;

  setUp(() {
    secrets = _MemorySecrets();
    authorizer = _FakeAuthorizer();
  });

  test(
    'Google reads require explicit read-only OAuth and never read local tasks',
    () async {
      final requests = <http.Request>[];
      final connector = GoogleTasksConnector(
        storage: secrets,
        authorizer: authorizer,
        now: () => fixedNow,
        clientFactory: () => MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/users/@me/lists')) {
            return http.Response(
              jsonEncode({
                'items': [
                  {'id': 'default', 'title': 'My Tasks'},
                ],
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'items': [
                {'id': 'task-1', 'title': 'Study', 'status': 'needsAction'},
              ],
            }),
            200,
          );
        }),
      );

      await expectLater(
        connector.listTaskLists(),
        throwsA(isA<GoogleTasksException>()),
      );
      await connector.connectReadOnly();
      expect(authorizer.requestedScopes.single, [
        GoogleTasksConnector.readonlyScope,
      ]);
      expect(await connector.connectedEmail, 'himangshuraj@gmail.com');
      expect(await connector.canEdit, isFalse);

      final lists = await connector.listTaskLists();
      expect(lists.single.title, 'My Tasks');
      final tasks = await connector.listTasks(lists.single.id);
      expect(tasks.single.title, 'Study');
      expect(requests, hasLength(2));
      expect(
        requests.every(
          (r) => r.headers['authorization'] == 'Bearer test-token',
        ),
        isTrue,
      );
    },
  );

  test('write is rejected until a separately approved write scope; then uses explicit API calls', () async {
    final requests = <http.Request>[];
    final connector = GoogleTasksConnector(
      storage: secrets,
      authorizer: authorizer,
      now: () => fixedNow,
      clientFactory: () => MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'id': 'new-task',
            'title': 'Review vectors',
            'status': 'needsAction',
          }),
          200,
        );
      }),
    );

    await connector.connectReadOnly();
    await expectLater(
      connector.addTask('default', 'Review vectors'),
      throwsA(
        isA<GoogleTasksException>().having(
          (e) => e.message,
          'message',
          contains('Enable task editing'),
        ),
      ),
    );
    expect(requests, isEmpty);

    await connector.enableEditing();
    expect(authorizer.requestedScopes.last, [GoogleTasksConnector.writeScope]);
    expect(await connector.canEdit, isTrue);
    final task = await connector.addTask('default', ' Review vectors ');
    expect(task.id, 'new-task');
    expect(requests.single.method, 'POST');
    expect(jsonDecode(requests.single.body), {'title': 'Review vectors'});

    await connector.setTaskCompleted('default', task, true);
    expect(requests.last.method, 'PATCH');
    expect(jsonDecode(requests.last.body), {'status': 'completed'});
  });

  test(
    'expired or unauthorized tokens are removed and never silently retried',
    () async {
      var calls = 0;
      final connector = GoogleTasksConnector(
        storage: secrets,
        authorizer: authorizer,
        now: () => fixedNow,
        clientFactory: () => MockClient((request) async {
          calls++;
          return http.Response('{}', 401);
        }),
      );
      await connector.connectReadOnly();
      await expectLater(
        connector.listTaskLists(),
        throwsA(isA<GoogleTasksException>()),
      );
      expect(calls, 1);
      expect(await connector.connectedEmail, isNull);
      expect(await secrets.read(key: 'google_tasks_access_token'), isNull);
      await expectLater(
        connector.listTaskLists(),
        throwsA(isA<GoogleTasksException>()),
      );
      expect(calls, 1);
    },
  );

  test('locally expired access token is cleared before any API call', () async {
    var now = fixedNow;
    var calls = 0;
    final connector = GoogleTasksConnector(
      storage: secrets,
      authorizer: authorizer,
      now: () => now,
      clientFactory: () => MockClient((request) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    await connector.connectReadOnly();
    now = fixedNow.add(const Duration(minutes: 56));
    await expectLater(
      connector.listTaskLists(),
      throwsA(
        isA<GoogleTasksException>().having(
          (e) => e.message,
          'message',
          contains('access expired'),
        ),
      ),
    );
    expect(calls, 0);
    expect(await connector.connectedEmail, isNull);
    expect(await secrets.read(key: 'google_tasks_access_token'), isNull);
  });

  test(
    'disconnect clears stored credentials and revokes provider session',
    () async {
      final connector = GoogleTasksConnector(
        storage: secrets,
        authorizer: authorizer,
        now: () => fixedNow,
      );
      await connector.connectReadOnly();
      await connector.disconnect();
      expect(await connector.connectedEmail, isNull);
      expect(await secrets.read(key: 'google_tasks_access_token'), isNull);
      expect(authorizer.disconnectCalls, 1);
    },
  );
}

class _MemorySecrets implements GoogleTasksSecretStore {
  final Map<String, String> values = {};
  @override
  Future<String?> read({required String key}) async => values[key];
  @override
  Future<void> write({required String key, required String value}) async =>
      values[key] = value;
  @override
  Future<void> delete({required String key}) async => values.remove(key);
}

class _FakeAuthorizer implements GoogleTasksAuthorizer {
  final requestedScopes = <List<String>>[];
  int disconnectCalls = 0;
  @override
  Future<GoogleTasksCredentials> authorize(List<String> scopes) async {
    requestedScopes.add(List<String>.from(scopes));
    return const GoogleTasksCredentials(
      email: 'himangshuraj@gmail.com',
      accessToken: 'test-token',
    );
  }

  @override
  Future<void> disconnect() async => disconnectCalls++;
}
