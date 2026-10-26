import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_assistant/assistant_state.dart';
import 'package:personal_assistant/mcp_servers.dart';
import 'package:personal_assistant/wajo_oauth.dart';

class _FakeAuthorizer implements WajoOAuthAuthorizer {
  int authorizeCalls = 0;
  int refreshCalls = 0;

  @override
  Future<WajoOAuthTokens> authorize({
    required String clientId,
    required String redirectUri,
    required WajoOAuthMetadata metadata,
  }) async {
    authorizeCalls++;
    expect(clientId, 'native-client');
    expect(redirectUri, wajoRedirectUri);
    return WajoOAuthTokens(
      'access-secret-test',
      'refresh-secret-test',
      DateTime.now().add(const Duration(hours: 1)),
    );
  }

  @override
  Future<WajoOAuthTokens> refresh({
    required String clientId,
    required String redirectUri,
    required String refreshToken,
    required WajoOAuthMetadata metadata,
  }) async {
    refreshCalls++;
    return WajoOAuthTokens(
      'refreshed-access-test',
      refreshToken,
      DateTime.now().add(const Duration(hours: 1)),
    );
  }
}

Map<String, Object?> _resourceMetadata({
  String resource = wajoResource,
  String issuer = wajoIssuer,
}) => {
  'resource': resource,
  'authorization_servers': [issuer],
};

Map<String, Object?> _issuerMetadata({
  String issuer = wajoIssuer,
  String authorizationEndpoint = 'https://mcp.api.wajo.ai/oauth/authorize',
  String tokenEndpoint = 'https://mcp.api.wajo.ai/oauth/token',
  String registrationEndpoint = 'https://mcp.api.wajo.ai/oauth/register',
}) => {
  'issuer': issuer,
  'authorization_endpoint': authorizationEndpoint,
  'token_endpoint': tokenEndpoint,
  'registration_endpoint': registrationEndpoint,
  'code_challenge_methods_supported': ['S256'],
  'response_types_supported': ['code'],
  'grant_types_supported': ['authorization_code', 'refresh_token'],
  'token_endpoint_auth_methods_supported': ['none'],
  'scopes_supported': ['mcp'],
};

http.Response _json(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('Android AppAuth receiver registers the exact OAuth callback', () async {
    final manifest = await File('android/app/src/main/AndroidManifest.xml')
        .readAsString();
    final callback = Uri.parse(wajoRedirectUri);
    expect(callback.scheme, 'dev.personalagent.personal-assistant');
    expect(callback.host, 'oauth2redirect');
    expect(callback.path, isEmpty);
    expect(
      manifest,
      contains('android:name="net.openid.appauth.RedirectUriReceiverActivity"'),
    );
    expect(manifest, contains('android:scheme="${callback.scheme}"'));
    expect(manifest, contains('android:host="${callback.host}"'));
    expect(manifest, contains('android:exported="true"'));
  });

  test('Wajo preset add is local only and leaves OAuth disconnected', () async {
    var requests = 0;
    final state = AssistantState(
      storage: const FlutterSecureStorage(),
      clientFactory: () => MockClient((_) async {
        requests++;
        return _json({});
      }),
    );

    await state.addMcpServer(
      'Wajo Fo',
      wajoMcpEndpoint,
      '',
      authMode: McpAuthMode.wajoOAuth,
    );
    final server = state.customMcpServers.single;
    expect(server.endpoint, 'https://mcp.api.wajo.ai/fo');
    expect(server.authMode, McpAuthMode.wajoOAuth);
    expect(requests, 0);
    expect(await state.isMcpOAuthConnected(server), isFalse);
    expect(
      await state.storage.read(key: 'custom_mcp_servers_v1'),
      contains(wajoMcpEndpoint),
    );
    expect(
      await state.storage.read(key: 'custom_mcp_wajo_${server.id}_access'),
      isNull,
    );
    expect(
      await state.storage.read(key: 'custom_mcp_wajo_${server.id}_client_id'),
      isNull,
    );
    state.dispose();
  });

  test('rejects mismatched Wajo resource or issuer before client registration', () async {
    for (final invalid in [
      _resourceMetadata(resource: 'https://other.example/fo'),
      _resourceMetadata(issuer: 'https://attacker.example'),
    ]) {
      var registrationRequests = 0;
      final flow = WajoOAuthFlow(
        storage: const FlutterSecureStorage(),
        clientFactory: () => MockClient((request) async {
          if (request.method == 'POST') registrationRequests++;
          if (request.url.toString() ==
              'https://mcp.api.wajo.ai/.well-known/oauth-protected-resource/fo') {
            return _json(invalid);
          }
          return _json(_issuerMetadata());
        }),
      );
      await expectLater(
        flow.discoverMetadata(),
        throwsA(isA<WajoOAuthException>()),
      );
      expect(registrationRequests, 0);
    }
  });

  test(
    'rejects changed issuer, non-HTTPS or foreign authorization endpoints',
    () async {
      for (final metadata in [
        _issuerMetadata(issuer: 'https://attacker.example'),
        _issuerMetadata(
          authorizationEndpoint: 'http://mcp.api.wajo.ai/oauth/authorize',
        ),
        _issuerMetadata(
          authorizationEndpoint: 'https://attacker.example/oauth/authorize',
        ),
      ]) {
        final flow = WajoOAuthFlow(
          storage: const FlutterSecureStorage(),
          clientFactory: () => MockClient(
            (request) async => request.url.toString() == 'https://mcp.api.wajo.ai/.well-known/oauth-protected-resource/fo'
                ? _json(_resourceMetadata())
                : _json(metadata),
          ),
        );
        await expectLater(
          flow.discoverMetadata(),
          throwsA(isA<WajoOAuthException>()),
        );
      }
    },
  );

  test('rejects unsupported PKCE and unsafe callback URI', () async {
    final noS256 = _issuerMetadata()
      ..['code_challenge_methods_supported'] = ['plain'];
    final flow = WajoOAuthFlow(
      storage: const FlutterSecureStorage(),
      clientFactory: () => MockClient(
        (request) async => request.url.toString() == 'https://mcp.api.wajo.ai/.well-known/oauth-protected-resource/fo'
            ? _json(_resourceMetadata())
            : _json(noS256),
      ),
    );
    await expectLater(
      flow.discoverMetadata(),
      throwsA(isA<WajoOAuthException>()),
    );
    expect(WajoOAuthFlow.isValidRedirectUri(wajoRedirectUri), isTrue);
    for (final unsafe in [
      'https://attacker.example/oauth2redirect',
      'dev.personalagent.personal-assistant://wrong-host',
      'dev.personalagent.personal-assistant://oauth2redirect?next=https://evil',
      'dev.personalagent.personal-assistant://oauth2redirect#fragment',
    ]) {
      expect(WajoOAuthFlow.isValidRedirectUri(unsafe), isFalse, reason: unsafe);
    }
  });

  test(
    'Connect alone performs metadata discovery, DCR and token authorization',
    () async {
      final storage = const FlutterSecureStorage();
      final authorizer = _FakeAuthorizer();
      final methods = <String>[];
      final bodies = <Map<String, dynamic>>[];
      http.Client makeClient() {
        return MockClient((request) async {
          methods.add(request.method);
          expect(request.followRedirects, isFalse);
          if (request.url.path == '/.well-known/oauth-protected-resource/fo') {
            return _json(_resourceMetadata());
          }
          if (request.url.path == '/.well-known/oauth-authorization-server') {
            return _json(_issuerMetadata());
          }
          if (request.url.path == '/oauth/register') {
            expect(request.method, 'POST');
            expect(request.headers['content-type'], 'application/json');
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            bodies.add(body);
            expect(body['redirect_uris'], [wajoRedirectUri]);
            expect(body['token_endpoint_auth_method'], 'none');
            expect(body['scope'], 'mcp');
            expect(body.containsKey('client_secret'), isFalse);
            return _json({
              'client_id': 'native-client',
              'redirect_uris': [wajoRedirectUri],
            }, status: 201);
          }
          fail('Unexpected request ${request.method} ${request.url}');
        });
      }

      final flow = WajoOAuthFlow(
        storage: storage,
        clientFactory: makeClient,
        authorizer: authorizer,
      );
      const server = McpServer(
        id: 'mcp-wajo',
        name: 'Wajo Fo',
        endpoint: wajoMcpEndpoint,
        authMode: McpAuthMode.wajoOAuth,
      );

      await flow.connect(server);

      expect(methods, ['GET', 'GET', 'POST']);
      expect(bodies, hasLength(1));
      expect(authorizer.authorizeCalls, 1);
      expect(await flow.isConnected(server), isTrue);
      expect(
        await storage.read(key: 'custom_mcp_wajo_mcp-wajo_access'),
        'access-secret-test',
      );
      expect(
        await storage.read(key: 'custom_mcp_wajo_mcp-wajo_refresh'),
        'refresh-secret-test',
      );
      expect(
        await storage.read(key: 'custom_mcp_wajo_mcp-wajo_client_id'),
        'native-client',
      );
      expect(await storage.read(key: 'custom_mcp_servers_v1'), isNull);
    },
  );

  test(
    'refuses altered DCR redirect and client secrets before authorization',
    () async {
      final authorizer = _FakeAuthorizer();
      http.Client makeClient() {
        return MockClient((request) async {
          if (request.url.path == '/.well-known/oauth-protected-resource/fo') {
            return _json(_resourceMetadata());
          }
          if (request.url.path == '/.well-known/oauth-authorization-server') {
            return _json(_issuerMetadata());
          }
          return _json({
            'client_id': 'native-client',
            'client_secret': 'must-not-be-stored',
            'redirect_uris': ['https://attacker.example/callback'],
          }, status: 201);
        });
      }

      for (var attempt = 0; attempt < 2; attempt++) {
        final storage = const FlutterSecureStorage();
        final flow = WajoOAuthFlow(
          storage: storage,
          clientFactory: makeClient,
          authorizer: authorizer,
        );
        const server = McpServer(
          id: 'mcp-wajo',
          name: 'Wajo Fo',
          endpoint: wajoMcpEndpoint,
          authMode: McpAuthMode.wajoOAuth,
        );
        await expectLater(
          flow.connect(server),
          throwsA(isA<WajoOAuthException>()),
        );
        expect(authorizer.authorizeCalls, 0);
        expect(
          await storage.read(key: 'custom_mcp_wajo_mcp-wajo_access'),
          isNull,
        );
      }
    },
  );

  test(
    'unknown or expired token lifetime requires refresh authorization',
    () async {
      const server = McpServer(
        id: 'mcp-wajo',
        name: 'Wajo Fo',
        endpoint: wajoMcpEndpoint,
        authMode: McpAuthMode.wajoOAuth,
      );
      final storage = const FlutterSecureStorage();
      await storage.write(
        key: 'custom_mcp_wajo_mcp-wajo_access',
        value: 'old-access',
      );
      await storage.write(
        key: 'custom_mcp_wajo_mcp-wajo_refresh',
        value: 'refresh',
      );
      await storage.write(
        key: 'custom_mcp_wajo_mcp-wajo_client_id',
        value: 'native-client',
      );
      final authorizer = _FakeAuthorizer();
      final flow = WajoOAuthFlow(
        storage: storage,
        clientFactory: () => MockClient(
          (request) async =>
              request.url.path == '/.well-known/oauth-protected-resource/fo'
              ? _json(_resourceMetadata())
              : _json(_issuerMetadata()),
        ),
        authorizer: authorizer,
      );

      expect(
        await flow.accessTokenForDiscovery(server),
        'refreshed-access-test',
      );
      expect(authorizer.refreshCalls, 1);
      expect(
        await storage.read(key: 'custom_mcp_wajo_mcp-wajo_access'),
        'refreshed-access-test',
      );

      await storage.delete(key: 'custom_mcp_wajo_mcp-wajo_expires_at');
      await storage.delete(key: 'custom_mcp_wajo_mcp-wajo_refresh');
      await expectLater(
        flow.accessTokenForDiscovery(server),
        throwsA(isA<WajoOAuthException>()),
      );
    },
  );

  test(
    'OAuth access token is used only for explicit bounded MCP requests',
    () async {
      final storage = const FlutterSecureStorage();
      const server = McpServer(
        id: 'mcp-wajo',
        name: 'Wajo Fo',
        endpoint: wajoMcpEndpoint,
        authMode: McpAuthMode.wajoOAuth,
      );
      final methods = <String>[];
      final store = McpServerStore(
        storage,
        () => MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          methods.add(body['method'] as String);
          expect(request.url.toString(), wajoMcpEndpoint);
          expect(request.headers['Authorization'], 'Bearer access-secret-test');
          expect(body.containsKey('messages'), isFalse);
          expect(body.containsKey('context'), isFalse);
          if (body['method'] == 'initialize') {
            return _json({
              'jsonrpc': '2.0',
              'id': body['id'],
              'result': {'protocolVersion': McpServerStore.protocolVersion},
            });
          }
          if (body['method'] == 'notifications/initialized') {
            return http.Response('', 202);
          }
          expect(body['method'], 'tools/list');
          return _json({
            'jsonrpc': '2.0',
            'id': body['id'],
            'result': {'tools': []},
          });
        }),
      );
      await store.discoverTools(server, oauthAccessToken: 'access-secret-test');
      expect(methods, [
        'initialize',
        'notifications/initialized',
        'tools/list',
      ]);
      expect(methods, isNot(contains('tools/call')));
    },
  );
}
