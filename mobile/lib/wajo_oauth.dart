import 'dart:async';
import 'dart:convert';

import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'mcp_servers.dart';

const wajoMcpEndpoint = 'https://mcp.api.wajo.ai/fo';
const wajoResource = 'https://mcp.api.wajo.ai/fo';
const wajoIssuer = 'https://mcp.api.wajo.ai';
const wajoRedirectUri = 'dev.personalagent.personal-assistant://oauth2redirect';

const _resourceMetadataUrl =
    'https://mcp.api.wajo.ai/.well-known/oauth-protected-resource/fo';
const _issuerMetadataUrl =
    'https://mcp.api.wajo.ai/.well-known/oauth-authorization-server';
const _authorizationEndpoint = 'https://mcp.api.wajo.ai/oauth/authorize';
const _tokenEndpoint = 'https://mcp.api.wajo.ai/oauth/token';
const _registrationEndpoint = 'https://mcp.api.wajo.ai/oauth/register';

class WajoOAuthException implements Exception {
  final String message;
  const WajoOAuthException(this.message);
  @override
  String toString() => message;
}

class WajoOAuthMetadata {
  final String authorizationEndpoint;
  final String tokenEndpoint;
  final String registrationEndpoint;
  const WajoOAuthMetadata({
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    required this.registrationEndpoint,
  });
}

class WajoOAuthTokens {
  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;
  const WajoOAuthTokens(this.accessToken, this.refreshToken, this.expiresAt);
}

abstract interface class WajoOAuthAuthorizer {
  Future<WajoOAuthTokens> authorize({
    required String clientId,
    required String redirectUri,
    required WajoOAuthMetadata metadata,
  });

  Future<WajoOAuthTokens> refresh({
    required String clientId,
    required String redirectUri,
    required String refreshToken,
    required WajoOAuthMetadata metadata,
  });
}

/// AppAuth creates an unpredictable state and S256 PKCE verifier, checks the
/// returned state against the saved request, and uses the system browser.
class AppAuthWajoAuthorizer implements WajoOAuthAuthorizer {
  final FlutterAppAuth appAuth;
  const AppAuthWajoAuthorizer({this.appAuth = const FlutterAppAuth()});

  AuthorizationServiceConfiguration _configuration(
    WajoOAuthMetadata metadata,
  ) => AuthorizationServiceConfiguration(
    authorizationEndpoint: metadata.authorizationEndpoint,
    tokenEndpoint: metadata.tokenEndpoint,
  );

  @override
  Future<WajoOAuthTokens> authorize({
    required String clientId,
    required String redirectUri,
    required WajoOAuthMetadata metadata,
  }) async {
    try {
      final configuration = _configuration(metadata);
      final authorization = await appAuth.authorize(
        AuthorizationRequest(
          clientId,
          redirectUri,
          serviceConfiguration: configuration,
          scopes: const ['mcp'],
          additionalParameters: const {'resource': wajoResource},
        ),
      );
      final code = authorization.authorizationCode;
      final verifier = authorization.codeVerifier;
      if (code == null ||
          code.isEmpty ||
          verifier == null ||
          verifier.isEmpty) {
        throw const WajoOAuthException(
          'Wajo authorization did not return a valid authorization code.',
        );
      }
      final response = await appAuth.token(
        TokenRequest(
          clientId,
          redirectUri,
          authorizationCode: code,
          codeVerifier: verifier,
          serviceConfiguration: configuration,
          scopes: const ['mcp'],
          additionalParameters: const {'resource': wajoResource},
        ),
      );
      final access = response.accessToken;
      if (access == null ||
          access.isEmpty ||
          response.tokenType?.toLowerCase() != 'bearer') {
        throw const WajoOAuthException(
          'Wajo did not return a usable bearer access token.',
        );
      }
      return WajoOAuthTokens(
        access,
        response.refreshToken,
        response.accessTokenExpirationDateTime,
      );
    } catch (error) {
      if (error is WajoOAuthException) rethrow;
      // AppAuth exceptions can include authorization URLs and codes. Never
      // surface their raw text to widgets, logs, or crash-reporting hooks.
      throw const WajoOAuthException(
        'OAuth authorization did not complete. You can try Connect again.',
      );
    }
  }

  @override
  Future<WajoOAuthTokens> refresh({
    required String clientId,
    required String redirectUri,
    required String refreshToken,
    required WajoOAuthMetadata metadata,
  }) async {
    try {
      final response = await appAuth.token(
        TokenRequest(
          clientId,
          redirectUri,
          refreshToken: refreshToken,
          serviceConfiguration: _configuration(metadata),
          scopes: const ['mcp'],
          additionalParameters: const {'resource': wajoResource},
        ),
      );
      final access = response.accessToken;
      if (access == null ||
          access.isEmpty ||
          response.tokenType?.toLowerCase() != 'bearer') {
        throw const WajoOAuthException(
          'Wajo did not return a usable bearer access token.',
        );
      }
      return WajoOAuthTokens(
        access,
        response.refreshToken ?? refreshToken,
        response.accessTokenExpirationDateTime,
      );
    } catch (error) {
      if (error is WajoOAuthException) rethrow;
      throw const WajoOAuthException(
        'Wajo authorization expired. Choose Connect with OAuth to sign in again.',
      );
    }
  }
}

class WajoOAuthFlow {
  final FlutterSecureStorage storage;
  final http.Client Function() clientFactory;
  final WajoOAuthAuthorizer authorizer;

  WajoOAuthFlow({
    required this.storage,
    required this.clientFactory,
    this.authorizer = const AppAuthWajoAuthorizer(),
  });

  String _key(McpServer server, String part) =>
      'custom_mcp_wajo_${server.id}_$part';

  bool supports(McpServer server) =>
      server.authMode == McpAuthMode.wajoOAuth &&
      server.endpoint == wajoMcpEndpoint;

  Future<bool> isConnected(McpServer server) async =>
      supports(server) &&
      (await storage.read(key: _key(server, 'access')))?.isNotEmpty == true;

  Future<WajoOAuthMetadata> discoverMetadata() async {
    final client = clientFactory();
    try {
      final resource = await _getJson(client, _resourceMetadataUrl);
      if (resource['resource'] != wajoResource ||
          resource['authorization_servers'] is! List ||
          !(resource['authorization_servers'] as List).contains(wajoIssuer)) {
        throw const WajoOAuthException(
          'Wajo OAuth metadata does not identify the requested MCP resource and issuer.',
        );
      }
      final issuer = await _getJson(client, _issuerMetadataUrl);
      if (issuer['issuer'] != wajoIssuer ||
          issuer['authorization_endpoint'] != _authorizationEndpoint ||
          issuer['token_endpoint'] != _tokenEndpoint ||
          issuer['registration_endpoint'] != _registrationEndpoint ||
          !_hasString(issuer['code_challenge_methods_supported'], 'S256') ||
          !_hasString(issuer['response_types_supported'], 'code') ||
          !_hasString(issuer['grant_types_supported'], 'authorization_code') ||
          !_hasString(
            issuer['token_endpoint_auth_methods_supported'],
            'none',
          ) ||
          !_hasString(issuer['scopes_supported'], 'mcp')) {
        throw const WajoOAuthException(
          'Wajo OAuth metadata changed or does not meet the supported native-app security requirements.',
        );
      }
      for (final endpoint in [
        issuer['authorization_endpoint'],
        issuer['token_endpoint'],
        issuer['registration_endpoint'],
      ]) {
        _validateExactHttpsEndpoint(endpoint);
      }
      return const WajoOAuthMetadata(
        authorizationEndpoint: _authorizationEndpoint,
        tokenEndpoint: _tokenEndpoint,
        registrationEndpoint: _registrationEndpoint,
      );
    } on WajoOAuthException {
      rethrow;
    } catch (_) {
      throw const WajoOAuthException(
        'Could not verify Wajo OAuth metadata. No credentials were sent.',
      );
    } finally {
      client.close();
    }
  }

  Future<String> _registerClient(
    http.Client client,
    WajoOAuthMetadata metadata,
  ) async {
    final request =
        http.Request('POST', Uri.parse(metadata.registrationEndpoint))
          ..followRedirects = false
          ..headers['content-type'] = 'application/json'
          ..headers['accept'] = 'application/json'
          ..body = jsonEncode({
            'client_name': 'Personal Agentic AI',
            'redirect_uris': [wajoRedirectUri],
            'token_endpoint_auth_method': 'none',
            'grant_types': ['authorization_code', 'refresh_token'],
            'response_types': ['code'],
            'scope': 'mcp',
          });
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 12));
    final body = await _readBody(response, limit: 32 * 1024);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const WajoOAuthException(
        'Wajo did not accept native-app client registration. No sign-in was started.',
      );
    }
    final decoded = _decodeJson(body);
    final clientId = decoded['client_id'];
    if (clientId is! String ||
        clientId.isEmpty ||
        clientId.length > 512 ||
        decoded.containsKey('client_secret')) {
      throw const WajoOAuthException(
        'Wajo returned an unsupported OAuth client registration response.',
      );
    }
    final redirects = decoded['redirect_uris'];
    if (redirects is! List ||
        redirects.length != 1 ||
        redirects.single != wajoRedirectUri) {
      throw const WajoOAuthException(
        'Wajo registered a different OAuth redirect URI; authorization was stopped.',
      );
    }
    return clientId;
  }

  /// This is called only from an explicit Connect tap, never while adding or
  /// selecting the local preset.
  Future<void> connect(McpServer server) async {
    if (!supports(server)) {
      throw const WajoOAuthException(
        'This OAuth flow is only for the Wajo Fo preset.',
      );
    }
    if (server.endpoint != wajoMcpEndpoint ||
        !isValidRedirectUri(wajoRedirectUri)) {
      throw const WajoOAuthException(
        'The Wajo endpoint or app redirect URI is invalid.',
      );
    }
    final metadata = await discoverMetadata();
    var clientId = await storage.read(key: _key(server, 'client_id'));
    if (clientId == null || clientId.isEmpty) {
      final client = clientFactory();
      try {
        clientId = await _registerClient(client, metadata);
      } finally {
        client.close();
      }
      // Client IDs are public identifiers, but are kept in secure storage next
      // to the credentials and never written to the server-list JSON.
      await storage.write(key: _key(server, 'client_id'), value: clientId);
    }
    final tokens = await authorizer.authorize(
      clientId: clientId,
      redirectUri: wajoRedirectUri,
      metadata: metadata,
    );
    await _saveTokens(server, tokens);
    // The manually pasted-token path is unused for this preset.
    await storage.delete(key: 'custom_mcp_token_${server.id}');
  }

  Future<void> _saveTokens(McpServer server, WajoOAuthTokens tokens) async {
    if (tokens.accessToken.isEmpty ||
        tokens.accessToken.length > 16 * 1024 ||
        (tokens.refreshToken?.length ?? 0) > 16 * 1024) {
      throw const WajoOAuthException(
        'Wajo returned an invalid token response.',
      );
    }
    await storage.write(key: _key(server, 'access'), value: tokens.accessToken);
    if (tokens.refreshToken != null && tokens.refreshToken!.isNotEmpty) {
      await storage.write(
        key: _key(server, 'refresh'),
        value: tokens.refreshToken,
      );
    }
    if (tokens.expiresAt != null) {
      await storage.write(
        key: _key(server, 'expires_at'),
        value: tokens.expiresAt!.millisecondsSinceEpoch.toString(),
      );
    } else {
      await storage.delete(key: _key(server, 'expires_at'));
    }
  }

  Future<String> accessTokenForDiscovery(McpServer server) async {
    if (!supports(server)) {
      throw const WajoOAuthException(
        'This OAuth flow is only for the Wajo Fo preset.',
      );
    }
    final token = await storage.read(key: _key(server, 'access'));
    if (token == null || token.isEmpty) {
      throw const WajoOAuthException(
        'Choose Connect with OAuth before testing this server.',
      );
    }
    final expiryText = await storage.read(key: _key(server, 'expires_at'));
    final expiry = int.tryParse(expiryText ?? '');
    if (expiry != null &&
        expiry >
            DateTime.now()
                .add(const Duration(minutes: 1))
                .millisecondsSinceEpoch) {
      return token;
    }
    final refreshToken = await storage.read(key: _key(server, 'refresh'));
    final clientId = await storage.read(key: _key(server, 'client_id'));
    if (refreshToken == null || clientId == null) {
      throw const WajoOAuthException(
        'Wajo authorization expired. Choose Connect with OAuth to sign in again.',
      );
    }
    final metadata = await discoverMetadata();
    final refreshed = await authorizer.refresh(
      clientId: clientId,
      redirectUri: wajoRedirectUri,
      refreshToken: refreshToken,
      metadata: metadata,
    );
    await _saveTokens(server, refreshed);
    return refreshed.accessToken;
  }

  Future<void> remove(McpServer server) async {
    for (final part in ['access', 'refresh', 'expires_at', 'client_id']) {
      await storage.delete(key: _key(server, part));
    }
    await storage.delete(key: 'custom_mcp_token_${server.id}');
  }

  static bool isValidRedirectUri(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.scheme == 'dev.personalagent.personal-assistant' &&
        uri.host == 'oauth2redirect' &&
        uri.path.isEmpty &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment;
  }

  static bool _hasString(Object? values, String expected) =>
      values is List && values.contains(expected);

  static void _validateExactHttpsEndpoint(Object? value) {
    if (value is! String) {
      throw const WajoOAuthException(
        'Wajo OAuth endpoint metadata is invalid.',
      );
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'mcp.api.wajo.ai' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !const [
          '/oauth/authorize',
          '/oauth/token',
          '/oauth/register',
        ].contains(uri.path)) {
      throw const WajoOAuthException(
        'Wajo OAuth metadata contains an untrusted endpoint.',
      );
    }
  }

  Future<Map<String, dynamic>> _getJson(
    http.Client client,
    String rawUrl,
  ) async {
    final request = http.Request('GET', Uri.parse(rawUrl))
      ..followRedirects = false
      ..headers['accept'] = 'application/json';
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 12));
    final body = await _readBody(response, limit: 32 * 1024);
    if (response.statusCode != 200 ||
        !(response.headers['content-type'] ?? '').toLowerCase().contains(
          'json',
        )) {
      throw const WajoOAuthException(
        'Wajo OAuth discovery did not return safe JSON metadata.',
      );
    }
    return _decodeJson(body);
  }

  Future<List<int>> _readBody(
    http.StreamedResponse response, {
    required int limit,
  }) async {
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 12),
    )) {
      if (bytes.length + chunk.length > limit) {
        throw const WajoOAuthException(
          'Wajo OAuth response exceeded the size limit.',
        );
      }
      bytes.addAll(chunk);
    }
    return bytes;
  }

  Map<String, dynamic> _decodeJson(List<int> body) {
    try {
      final decoded = jsonDecode(utf8.decode(body, allowMalformed: false));
      if (decoded is! Map<String, dynamic>) {
        throw const WajoOAuthException(
          'Wajo OAuth returned invalid JSON metadata.',
        );
      }
      return decoded;
    } catch (_) {
      throw const WajoOAuthException(
        'Wajo OAuth returned invalid JSON metadata.',
      );
    }
  }
}
