import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_assistant/assistant_state.dart';
import 'package:personal_assistant/mcp_servers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('validates endpoint transport and server names', () async {
    expect(() => validateMcpServer('  ', 'https://mcp.example/mcp'), throwsA(isA<McpException>()));
    expect(() => validateMcpServer('x'.padRight(49, 'x'), 'https://mcp.example/mcp'), throwsA(isA<McpException>()));
    expect(() => validateMcpEndpoint('http://public.example/mcp'), throwsA(isA<McpException>()));
    expect(() => validateMcpEndpoint('https://user:pass@mcp.example/mcp'), throwsA(isA<McpException>()));
    expect(() => validateMcpEndpoint('https://mcp.example/mcp?token=secret'), throwsA(isA<McpException>()));
    expect(validateMcpEndpoint('https://mcp.example/mcp').path, '/mcp');
    expect(validateMcpEndpoint('http://10.0.2.2:8080/mcp').host, '10.0.2.2');
    final storage = const FlutterSecureStorage();
    final store = McpServerStore(storage, () => MockClient((_) async => http.Response('', 500)));
    await expectLater(
      store.setBearerToken('mcp-test', 'token with spaces'),
      throwsA(isA<McpException>()),
    );
  });

  test('AssistantState add/remove flow survives reload and blocks duplicate names', () async {
    final storage = const FlutterSecureStorage();
    final state = AssistantState(storage: storage);
    await state.addMcpServer('  Local tools  ', 'https://mcp.example/mcp', 'test-token');
    expect(state.customMcpServers.single.name, 'Local tools');
    expect(await storage.read(key: 'custom_mcp_servers_v1'), isNot(contains('test-token')));
    expect(await storage.read(key: 'custom_mcp_token_${state.customMcpServers.single.id}'), 'test-token');
    await expectLater(
      state.addMcpServer('local TOOLS', 'https://other.example/mcp', ''),
      throwsA(isA<McpException>()),
    );
    final reloaded = AssistantState(storage: storage);
    await reloaded.initialize();
    expect(reloaded.customMcpServers.single.name, 'Local tools');
    await reloaded.removeMcpServer(reloaded.customMcpServers.single.id);
    expect(await reloaded.mcpStore.load(), isEmpty);
    expect(await storage.read(key: 'custom_mcp_token_${state.customMcpServers.single.id}'), isNull);
    state.dispose();
    reloaded.dispose();
  });

  test('persists validated servers and keeps bearer token out of server metadata', () async {
    final storage = const FlutterSecureStorage();
    final store = McpServerStore(storage, () => MockClient((_) async => http.Response('', 500)));
    final server = const McpServer(id: 'mcp-test', name: 'Local tools', endpoint: 'https://mcp.example/mcp');
    await store.save([server]);
    await store.setBearerToken(server.id, 'private-test-token');
    final persisted = await storage.read(key: 'custom_mcp_servers_v1');
    expect(persisted, contains('Local tools'));
    expect(persisted, isNot(contains('private-test-token')));
    expect(await storage.read(key: 'custom_mcp_token_mcp-test'), 'private-test-token');
    expect((await store.load()).single.endpoint, server.endpoint);
    await store.remove(server, [server]);
    expect(await store.load(), isEmpty);
    expect(await storage.read(key: 'custom_mcp_token_mcp-test'), isNull);
  });

  test('tests connection and discovers tools without invoking them or sending context', () async {
    final storage = const FlutterSecureStorage();
    final server = const McpServer(id: 'mcp-test', name: 'Mock', endpoint: 'https://mcp.example/mcp');
    await storage.write(key: 'custom_mcp_token_${server.id}', value: 'secret-test-token');
    final calls = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.toString(), server.endpoint);
      expect(request.followRedirects, isFalse);
      expect(request.headers['Authorization'], 'Bearer secret-test-token');
      expect(request.headers['Accept'], 'application/json, text/event-stream');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      calls.add(body);
      if (body['method'] == 'initialize') {
        expect(request.headers.containsKey('MCP-Protocol-Version'), isFalse);
        return http.Response(jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': {'protocolVersion': McpServerStore.protocolVersion, 'capabilities': {'tools': {}}, 'serverInfo': {'name': 'mock', 'version': '1'}}}), 200, headers: {'content-type': 'application/json', 'mcp-session-id': 'session-one'});
      }
      if (body['method'] == 'notifications/initialized') {
        expect(body.containsKey('id'), isFalse);
        expect(request.headers['Mcp-Session-Id'], 'session-one');
        expect(request.headers['MCP-Protocol-Version'], McpServerStore.protocolVersion);
        return http.Response('', 202);
      }
      if (body['method'] == 'tools/list') {
        expect(request.headers['Mcp-Session-Id'], 'session-one');
        expect(request.headers['MCP-Protocol-Version'], McpServerStore.protocolVersion);
        expect(body['params'], isEmpty);
        return http.Response(jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': {'tools': [{'name': 'lookup', 'description': 'Read-only example'}]}}), 200, headers: {'content-type': 'application/json'});
      }
      fail('Unexpected MCP method ${body['method']}');
    });
    final store = McpServerStore(storage, () => client);
    final tools = await store.discoverTools(server);
    expect(tools.map((tool) => tool.name), ['lookup']);
    expect(calls.map((call) => call['method']), ['initialize', 'notifications/initialized', 'tools/list']);
    expect(calls.any((call) => call['method'] == 'tools/call'), isFalse);
    expect(calls.every((call) => !call.containsKey('messages') && !call.containsKey('context')), isTrue);
  });

  test('rejects unbounded SSE responses instead of hanging on a server event stream', () async {
    final storage = const FlutterSecureStorage();
    final server = const McpServer(id: 'mcp-sse', name: 'SSE', endpoint: 'https://mcp.example/mcp');
    final client = MockClient((request) async {
      return http.Response(
        'event: message\ndata: {"jsonrpc":"2.0","id":1,"result":{}}\n\n',
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    final store = McpServerStore(storage, () => client);
    await expectLater(store.discoverTools(server), throwsA(isA<McpException>()));
  });
}
