import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_assistant/assistant_state.dart';
import 'package:personal_assistant/mcp_servers.dart';

const _server = McpServer(
  id: 'mcp-test',
  name: 'Mock tools',
  endpoint: 'https://mcp.example/mcp',
);
const _token = 'secret-test-token';

http.Response _rpc(
  Map<String, dynamic> body, {
  int status = 200,
  Map<String, String> headers = const {},
}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json', ...headers},
);

Map<String, dynamic> _success(Object id, Map<String, dynamic> result) => {
  'jsonrpc': '2.0',
  'id': id,
  'result': result,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('validates endpoint transport and server names', () async {
    expect(
      () => validateMcpServer('  ', 'https://mcp.example/mcp'),
      throwsA(isA<McpException>()),
    );
    expect(
      () => validateMcpServer('x'.padRight(49, 'x'), 'https://mcp.example/mcp'),
      throwsA(isA<McpException>()),
    );
    expect(
      () => validateMcpEndpoint('http://public.example/mcp'),
      throwsA(isA<McpException>()),
    );
    expect(
      () => validateMcpEndpoint('https://user:pass@mcp.example/mcp'),
      throwsA(isA<McpException>()),
    );
    expect(
      () => validateMcpEndpoint('https://mcp.example/mcp?token=secret'),
      throwsA(isA<McpException>()),
    );
    expect(validateMcpEndpoint('https://mcp.example/mcp').path, '/mcp');
    expect(validateMcpEndpoint('http://10.0.2.2:8080/mcp').host, '10.0.2.2');
    final store = McpServerStore(
      const FlutterSecureStorage(),
      () => MockClient((_) async => http.Response('', 500)),
    );
    await expectLater(
      store.setBearerToken('mcp-test', 'token with spaces'),
      throwsA(isA<McpException>()),
    );
  });

  test('parses only bounded JSON object arguments', () {
    expect(validateMcpToolArguments('{"query":"hello"}'), {'query': 'hello'});
    expect(() => validateMcpToolArguments('[]'), throwsA(isA<McpException>()));
    expect(
      () => validateMcpToolArguments('{bad json'),
      throwsA(isA<McpException>()),
    );
    expect(
      () => validateMcpToolArguments('"${'x' * maxMcpToolArgumentsBytes}"'),
      throwsA(isA<McpException>()),
    );
    var nested = '0';
    for (var index = 0; index < 18; index++) {
      nested = '[$nested]';
    }
    expect(
      () => validateMcpToolArguments('{"deep":$nested}'),
      throwsA(isA<McpException>()),
    );
  });

  test(
    'AssistantState add/remove flow survives reload and blocks duplicate names',
    () async {
      final storage = const FlutterSecureStorage();
      final state = AssistantState(storage: storage);
      await state.addMcpServer(
        '  Local tools  ',
        'https://mcp.example/mcp',
        'test-token',
      );
      expect(state.customMcpServers.single.name, 'Local tools');
      expect(
        await storage.read(key: 'custom_mcp_servers_v1'),
        isNot(contains('test-token')),
      );
      expect(
        await storage.read(
          key: 'custom_mcp_token_${state.customMcpServers.single.id}',
        ),
        'test-token',
      );
      await expectLater(
        state.addMcpServer('local TOOLS', 'https://other.example/mcp', ''),
        throwsA(isA<McpException>()),
      );
      final reloaded = AssistantState(storage: storage);
      await reloaded.initialize();
      expect(reloaded.customMcpServers.single.name, 'Local tools');
      await reloaded.removeMcpServer(reloaded.customMcpServers.single.id);
      expect(await reloaded.mcpStore.load(), isEmpty);
      expect(
        await storage.read(
          key: 'custom_mcp_token_${state.customMcpServers.single.id}',
        ),
        isNull,
      );
      state.dispose();
      reloaded.dispose();
    },
  );

  test('persists server metadata without exposing its bearer token', () async {
    final storage = const FlutterSecureStorage();
    final store = McpServerStore(
      storage,
      () => MockClient((_) async => http.Response('', 500)),
    );
    await store.save([_server]);
    await store.setBearerToken(_server.id, 'private-test-token');
    final persisted = await storage.read(key: 'custom_mcp_servers_v1');
    expect(persisted, contains('Mock tools'));
    expect(persisted, isNot(contains('private-test-token')));
    expect(
      await storage.read(key: 'custom_mcp_token_mcp-test'),
      'private-test-token',
    );
    expect((await store.load()).single.endpoint, _server.endpoint);
    await store.remove(_server, [_server]);
    expect(await store.load(), isEmpty);
    expect(await storage.read(key: 'custom_mcp_token_mcp-test'), isNull);
  });

  test('discovers tools only and sends no chat or memory context', () async {
    final storage = const FlutterSecureStorage();
    await storage.write(key: 'custom_mcp_token_${_server.id}', value: _token);
    final calls = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.toString(), _server.endpoint);
      expect(request.followRedirects, isFalse);
      expect(request.headers['Authorization'], 'Bearer $_token');
      expect(request.headers['Accept'], 'application/json, text/event-stream');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      calls.add(body);
      if (body['method'] == 'initialize') {
        expect(request.headers.containsKey('MCP-Protocol-Version'), isFalse);
        return _rpc(
          _success(body['id'], {
            'protocolVersion': McpServerStore.protocolVersion,
            'capabilities': {'tools': {}},
            'serverInfo': {'name': 'mock', 'version': '1'},
          }),
          status: 200,
          headers: const {'mcp-session-id': 'session-one'},
        );
      }
      if (body['method'] == 'notifications/initialized') {
        expect(body.containsKey('id'), isFalse);
        expect(request.headers['Mcp-Session-Id'], 'session-one');
        expect(
          request.headers['MCP-Protocol-Version'],
          McpServerStore.protocolVersion,
        );
        return http.Response('', 202);
      }
      if (body['method'] == 'tools/list') {
        expect(request.headers['Mcp-Session-Id'], 'session-one');
        expect(
          request.headers['MCP-Protocol-Version'],
          McpServerStore.protocolVersion,
        );
        expect(body['params'] ?? const <String, dynamic>{}, isEmpty);
        return _rpc(
          _success(body['id'], {
            'tools': [
              {
                'name': 'lookup',
                'description': 'Read-only example',
                'inputSchema': {
                  'type': 'object',
                  'properties': {
                    'query': {'type': 'string'},
                  },
                },
              },
            ],
          }),
        );
      }
      fail('Unexpected MCP method ${body['method']}');
    });
    final store = McpServerStore(storage, () => client);
    final tools = await store.discoverTools(_server);
    expect(tools.single.name, 'lookup');
    expect(tools.single.inputSchema['type'], 'object');
    expect(calls.map((call) => call['method']), [
      'initialize',
      'notifications/initialized',
      'tools/list',
    ]);
    expect(calls.any((call) => call['method'] == 'tools/call'), isFalse);
    expect(
      calls.every(
        (call) => !call.containsKey('messages') && !call.containsKey('context'),
      ),
      isTrue,
    );
    expect(calls.every((call) => !jsonEncode(call).contains(_token)), isTrue);
  });

  test('calls exactly the reviewed tool and arguments; redacts echoed bearer token', () async {
    final storage = const FlutterSecureStorage();
    await storage.write(key: 'custom_mcp_token_${_server.id}', value: _token);
    final calls = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      expect(request.url.toString(), _server.endpoint);
      expect(request.followRedirects, isFalse);
      expect(request.headers['Authorization'], 'Bearer $_token');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      calls.add(body);
      if (body['method'] == 'initialize') {
        return _rpc(
          _success(body['id'], {
            'protocolVersion': McpServerStore.protocolVersion,
            'capabilities': {},
            'serverInfo': {'name': 'mock', 'version': '1'},
          }),
          status: 200,
        );
      }
      if (body['method'] == 'notifications/initialized') {
        return http.Response('', 202);
      }
      if (body['method'] == 'tools/call') {
        expect(body['params'], {
          'name': 'lookup',
          'arguments': {'query': 'my notes'},
        });
        return _rpc(
          _success(body['id'], {
            'content': [
              {'type': 'text', 'text': 'found $_token'},
            ],
            'isError': false,
          }),
        );
      }
      fail('Unexpected MCP method ${body['method']}');
    });

    final result = await McpServerStore(storage, () => client).callTool(
      _server,
      const McpToolInfo('lookup', 'Searches notes', {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
        },
      }),
      {'query': 'my notes'},
    );
    expect(calls.map((call) => call['method']), [
      'initialize',
      'notifications/initialized',
      'tools/call',
    ]);
    expect(
      calls.every(
        (call) => !call.containsKey('messages') && !call.containsKey('context'),
      ),
      isTrue,
    );
    expect(calls.every((call) => !jsonEncode(call).contains(_token)), isTrue);
    expect(result['isError'], isFalse);
    expect(result['content'][0]['text'], 'found [redacted]');
  });

  test(
    'rejects missing OAuth authorization without sending a request',
    () async {
      var requests = 0;
      final server = McpServer(
        id: 'mcp-wajo',
        name: 'Wajo Fo',
        endpoint: 'https://mcp.api.wajo.ai/fo',
        authMode: McpAuthMode.wajoOAuth,
      );
      final store = McpServerStore(
        const FlutterSecureStorage(),
        () => MockClient((_) async {
          requests++;
          return http.Response('', 500);
        }),
      );
      await expectLater(
        store.callTool(
          server,
          const McpToolInfo('lookup', '', {'type': 'object'}),
          {},
        ),
        throwsA(isA<McpException>()),
      );
      expect(requests, 0);
    },
  );

  test('rejects invalid JSON-RPC responses and redirects', () async {
    for (final invalidResponse in [
      _rpc({
        'jsonrpc': '1.0',
        'id': 1,
        'result': {'protocolVersion': McpServerStore.protocolVersion},
      }),
      _rpc({
        'jsonrpc': '2.0',
        'id': 7,
        'result': {'protocolVersion': McpServerStore.protocolVersion},
      }),
      _rpc({'jsonrpc': '2.0', 'id': 1, 'result': {}, 'error': {}}),
      http.Response(
        '',
        302,
        headers: const {'location': 'https://attacker.example/'},
      ),
    ]) {
      final store = McpServerStore(
        const FlutterSecureStorage(),
        () => MockClient((_) async => invalidResponse),
      );
      await expectLater(
        store.discoverTools(_server),
        throwsA(isA<McpException>()),
      );
    }
  });

  test('rejects an oversized MCP response', () async {
    final store = McpServerStore(
      const FlutterSecureStorage(),
      () => MockClient(
        (_) async => http.Response(
          '{"jsonrpc":"2.0","id":1,"result":{"value":"${'x' * maxMcpResponseBytes}"}}',
          200,
          headers: const {'content-type': 'application/json'},
        ),
      ),
    );
    await expectLater(
      store.discoverTools(_server),
      throwsA(isA<McpException>()),
    );
  });
}
