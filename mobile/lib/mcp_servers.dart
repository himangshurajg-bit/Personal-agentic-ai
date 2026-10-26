import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

enum McpAuthMode { bearer, wajoOAuth }

class McpServer {
  final String id;
  final String name;
  final String endpoint;
  final McpAuthMode authMode;
  const McpServer({
    required this.id,
    required this.name,
    required this.endpoint,
    this.authMode = McpAuthMode.bearer,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'endpoint': endpoint,
    'authMode': authMode.name,
  };

  factory McpServer.fromJson(Map<String, dynamic> value) => McpServer(
    id: value['id'] as String,
    name: value['name'] as String,
    endpoint: value['endpoint'] as String,
    authMode: value['authMode'] == McpAuthMode.wajoOAuth.name
        ? McpAuthMode.wajoOAuth
        : McpAuthMode.bearer,
  );
}

class McpToolInfo {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;
  const McpToolInfo(this.name, this.description, this.inputSchema);
}

class McpException implements Exception {
  final String message;
  const McpException(this.message);
  @override
  String toString() => message;
}

Uri validateMcpEndpoint(String raw) {
  final value = raw.trim();
  final uri = Uri.tryParse(value);
  if (value.isEmpty ||
      value.length > 2048 ||
      uri == null ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      !['https', 'http'].contains(uri.scheme) ||
      (uri.scheme == 'http' &&
          !const [
            'localhost',
            '127.0.0.1',
            '::1',
            '10.0.2.2',
          ].contains(uri.host))) {
    throw const McpException(
      'Use an HTTPS MCP endpoint. Plain HTTP is allowed only for localhost or the Android emulator.',
    );
  }
  return uri;
}

void validateMcpServer(String name, String endpoint) {
  final normalized = name.trim();
  if (normalized.isEmpty ||
      normalized.runes.length > 48 ||
      normalized.contains(RegExp(r'[\x00-\x1f]'))) {
    throw const McpException(
      'Server name must be 1–48 characters without control characters.',
    );
  }
  validateMcpEndpoint(endpoint);
}

const int maxMcpToolArgumentsBytes = 16 * 1024;
const int maxMcpResponseBytes = 256 * 1024;

/// Parses bounded JSON object arguments for an explicitly reviewed MCP tool call.
Map<String, dynamic> validateMcpToolArguments(String raw) {
  if (utf8.encode(raw).length > maxMcpToolArgumentsBytes) {
    throw const McpException('Tool arguments exceed the 16 KB safety limit.');
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const McpException('Tool arguments must be a JSON object.');
    }
    _validateJsonTree(decoded);
    return decoded;
  } on FormatException {
    throw const McpException('Enter valid JSON for the tool arguments.');
  }
}

void _validateJsonTree(Object? value, {int depth = 0, List<int>? count}) {
  final nodes = count ?? [0];
  nodes[0]++;
  if (depth > 16 || nodes[0] > 4096) {
    throw const McpException('Tool data is too deeply nested or complex.');
  }
  if (value == null || value is bool || value is String || value is num) return;
  if (value is List) {
    for (final item in value) {
      _validateJsonTree(item, depth: depth + 1, count: nodes);
    }
    return;
  }
  if (value is Map) {
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw const McpException(
          'Tool data contains an invalid JSON object key.',
        );
      }
      _validateJsonTree(entry.value, depth: depth + 1, count: nodes);
    }
    return;
  }
  throw const McpException('Tool data contains an unsupported JSON value.');
}

/// Stores endpoint metadata and keeps optional bearer credentials in a separate secure key.
class McpServerStore {
  static const protocolVersion = '2025-03-26';
  final FlutterSecureStorage storage;
  final http.Client Function() clientFactory;
  McpServerStore(this.storage, this.clientFactory);

  Future<List<McpServer>> load() async {
    final raw = await storage.read(key: 'custom_mcp_servers_v1');
    if (raw == null) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List || decoded.length > 25) {
      throw const McpException('Saved MCP server list is invalid.');
    }
    final result = <McpServer>[];
    final ids = <String>{};
    final names = <String>{};
    for (final item in decoded) {
      if (item is! Map) {
        throw const McpException('Saved MCP server entry is invalid.');
      }
      final server = McpServer.fromJson(Map<String, dynamic>.from(item));
      validateMcpServer(server.name, server.endpoint);
      if (!RegExp(r'^mcp-[A-Za-z0-9-]{1,60}$').hasMatch(server.id) ||
          !ids.add(server.id) ||
          !names.add(server.name.trim().toLowerCase())) {
        throw const McpException(
          'Saved MCP server identifier or name is invalid.',
        );
      }
      result.add(server);
    }
    return result;
  }

  Future<List<McpServer>> save(List<McpServer> servers) async {
    if (servers.length > 25) {
      throw const McpException('You can add up to 25 MCP servers.');
    }
    final ids = <String>{};
    final names = <String>{};
    for (final server in servers) {
      validateMcpServer(server.name, server.endpoint);
      if (!RegExp(r'^mcp-[A-Za-z0-9-]{1,60}$').hasMatch(server.id) ||
          !ids.add(server.id) ||
          !names.add(server.name.trim().toLowerCase())) {
        throw const McpException('Server IDs and names must be unique.');
      }
    }
    await storage.write(
      key: 'custom_mcp_servers_v1',
      value: jsonEncode(servers.map((s) => s.toJson()).toList()),
    );
    return List.unmodifiable(servers);
  }

  Future<void> setBearerToken(String id, String token) async {
    final validToken = RegExp(r'^[A-Za-z0-9\-._~+/]+=*$');
    if (!RegExp(r'^mcp-[A-Za-z0-9-]{1,60}$').hasMatch(id) ||
        token.length > 4096 ||
        (token.isNotEmpty && !validToken.hasMatch(token))) {
      throw const McpException(
        'Use a valid bearer token without spaces or line breaks.',
      );
    }
    final key = 'custom_mcp_token_$id';
    if (token.isEmpty) {
      await storage.delete(key: key);
    } else {
      await storage.write(key: key, value: token);
    }
  }

  Future<void> remove(McpServer server, List<McpServer> servers) async {
    await save(servers.where((s) => s.id != server.id).toList());
    await storage.delete(key: 'custom_mcp_token_${server.id}');
  }

  Future<List<McpToolInfo>> discoverTools(
    McpServer server, {
    String? oauthAccessToken,
  }) async {
    validateMcpServer(server.name, server.endpoint);
    final token = await _tokenFor(server, oauthAccessToken);
    final client = clientFactory();
    final connection = _McpJsonRpcConnection(client, server.endpoint, token);
    try {
      await connection.initialize();
      final tools = <McpToolInfo>[];
      final cursors = <String>{};
      String? cursor;
      for (var page = 0; page < 5; page++) {
        final params = <String, dynamic>{};
        if (cursor != null) params['cursor'] = cursor;
        final result = await connection.request('tools/list', params);
        final rawTools = result['tools'];
        if (rawTools is! List || tools.length + rawTools.length > 200) {
          throw const McpException(
            'MCP tools/list response is invalid or exceeds 200 tools.',
          );
        }
        for (final item in rawTools) {
          if (item is! Map ||
              item['name'] is! String ||
              (item['name'] as String).isEmpty ||
              (item['name'] as String).length > 128 ||
              (item['name'] as String).contains(RegExp(r'[\x00-\x1f]'))) {
            throw const McpException(
              'MCP server returned an invalid tool description.',
            );
          }
          final rawSchema = item['inputSchema'];
          if (rawSchema is! Map) {
            throw const McpException(
              'MCP server returned a tool without a valid input schema.',
            );
          }
          final schema = Map<String, dynamic>.from(rawSchema);
          if (utf8.encode(jsonEncode(schema)).length > 8192) {
            throw const McpException(
              'MCP tool input schema exceeds the safety limit.',
            );
          }
          _validateJsonTree(schema);
          final description = item['description'] is String
              ? item['description'] as String
              : '';
          tools.add(
            McpToolInfo(
              item['name'] as String,
              description.length <= 500
                  ? description
                  : '${description.substring(0, 500)}…',
              schema,
            ),
          );
        }
        final next = result['nextCursor'];
        if (next == null) return List.unmodifiable(tools);
        if (next is! String ||
            next.isEmpty ||
            next.length > 1024 ||
            !cursors.add(next)) {
          throw const McpException(
            'MCP server returned an invalid pagination cursor.',
          );
        }
        cursor = next;
      }
      throw const McpException(
        'MCP server has more than five pages of tools; discovery stopped safely.',
      );
    } on TimeoutException {
      throw const McpException('MCP server timed out. Nothing was retried.');
    } on FormatException {
      throw const McpException('MCP server returned invalid JSON.');
    } on http.ClientException {
      throw const McpException(
        'Could not reach the MCP server. Check its URL and connection.',
      );
    } on McpException {
      rethrow;
    } catch (_) {
      throw const McpException(
        'MCP connection or response could not be verified.',
      );
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> callTool(
    McpServer server,
    McpToolInfo tool,
    Map<String, dynamic> arguments, {
    String? oauthAccessToken,
  }) async {
    validateMcpServer(server.name, server.endpoint);
    if (tool.name.isEmpty ||
        tool.name.length > 128 ||
        tool.name.contains(RegExp(r'[\x00-\x1f]'))) {
      throw const McpException('MCP tool name is invalid.');
    }
    late final Map<String, dynamic> boundedArguments;
    try {
      boundedArguments = validateMcpToolArguments(jsonEncode(arguments));
    } on McpException {
      rethrow;
    } catch (_) {
      throw const McpException(
        'Tool arguments contain values that cannot be encoded as JSON.',
      );
    }
    final token = await _tokenFor(server, oauthAccessToken);
    final client = clientFactory();
    final connection = _McpJsonRpcConnection(client, server.endpoint, token);
    try {
      await connection.initialize();
      return await connection.request('tools/call', {
        'name': tool.name,
        'arguments': boundedArguments,
      });
    } on TimeoutException {
      throw const McpException(
        'MCP tool call timed out. Its outcome may be unknown; do not retry automatically.',
      );
    } on FormatException {
      throw const McpException('MCP server returned invalid JSON.');
    } on http.ClientException {
      throw const McpException(
        'Could not reach the MCP server. The tool outcome may be unknown.',
      );
    } on McpException {
      rethrow;
    } catch (_) {
      throw const McpException(
        'MCP tool call or response could not be verified.',
      );
    } finally {
      client.close();
    }
  }

  Future<String> _tokenFor(McpServer server, String? oauthAccessToken) async {
    final token = server.authMode == McpAuthMode.wajoOAuth
        ? (oauthAccessToken ?? '')
        : (await storage.read(key: 'custom_mcp_token_${server.id}') ?? '');
    if (server.authMode == McpAuthMode.wajoOAuth && token.isEmpty) {
      throw const McpException('Connect with OAuth before using this server.');
    }
    return token;
  }
}

class _McpJsonRpcConnection {
  final http.Client client;
  final String endpoint;
  final String token;
  int _requestId = 0;
  String? _sessionId;

  _McpJsonRpcConnection(this.client, this.endpoint, this.token);

  Future<void> initialize() async {
    final result = await request('initialize', {
      'protocolVersion': McpServerStore.protocolVersion,
      'capabilities': <String, dynamic>{},
      'clientInfo': {'name': 'Personal Agentic AI', 'version': '1.0.0'},
    });
    if (result['protocolVersion'] != McpServerStore.protocolVersion) {
      throw const McpException(
        'MCP server did not negotiate the supported protocol version.',
      );
    }
    await notify('notifications/initialized');
  }

  Future<Map<String, dynamic>> request(
    String method,
    Map<String, dynamic> params,
  ) async {
    final id = ++_requestId;
    final response = await _post(method, params, id: id);
    if (response['id'] != id) {
      throw const McpException('MCP response ID did not match the request.');
    }
    if (response.containsKey('error')) {
      final error = response['error'];
      if (error is! Map ||
          error['code'] is! int ||
          error['message'] is! String ||
          (error['message'] as String).length > 2048) {
        throw const McpException(
          'MCP server returned an invalid protocol error.',
        );
      }
      throw const McpException('MCP server rejected the protocol request.');
    }
    if (!response.containsKey('result') || response['result'] is! Map) {
      throw const McpException(
        'MCP server returned an invalid protocol result.',
      );
    }
    final result = Map<String, dynamic>.from(response['result'] as Map);
    _validateJsonTree(result);
    if (method == 'tools/call' &&
        result['isError'] != null &&
        result['isError'] is! bool) {
      throw const McpException('MCP server returned an invalid tool result.');
    }
    return result;
  }

  Future<void> notify(String method) async {
    final status = await _post(method, const {}, notification: true);
    if (status != 202 && status != 204) {
      throw const McpException(
        'MCP server did not acknowledge initialization.',
      );
    }
  }

  Future<dynamic> _post(
    String method,
    Map<String, dynamic> params, {
    int? id,
    bool notification = false,
  }) async {
    final body = <String, dynamic>{'jsonrpc': '2.0', 'method': method};
    if (!notification) body['id'] = id;
    if (params.isNotEmpty) body['params'] = params;
    final encoded = jsonEncode(body);
    if (utf8.encode(encoded).length > maxMcpToolArgumentsBytes + 4096) {
      throw const McpException('MCP request exceeds the 20 KB safety limit.');
    }
    final request = http.Request('POST', validateMcpEndpoint(endpoint))
      ..followRedirects = false
      ..headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/event-stream',
        if (method != 'initialize')
          'MCP-Protocol-Version': McpServerStore.protocolVersion,
        'Mcp-Session-Id': ?_sessionId,
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      })
      ..body = encoded;
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 12));
    final returnedSession = response.headers['mcp-session-id'];
    if (returnedSession != null) {
      if (returnedSession.isEmpty ||
          returnedSession.length > 256 ||
          returnedSession.contains(RegExp(r'[\r\n]'))) {
        throw const McpException(
          'MCP server returned an invalid session identifier.',
        );
      }
      _sessionId = returnedSession;
    }
    if (notification &&
        (response.statusCode == 202 || response.statusCode == 204)) {
      return response.statusCode;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw McpException('MCP server returned HTTP ${response.statusCode}.');
    }
    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.toLowerCase().contains('application/json')) {
      throw const McpException(
        'This build supports bounded JSON MCP responses, not SSE streams.',
      );
    }
    final bytes = <int>[];
    Future<List<int>> readResponse() async {
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > maxMcpResponseBytes) {
          throw const McpException(
            'MCP response exceeded the 256 KB safety limit.',
          );
        }
        bytes.addAll(chunk);
      }
      return bytes;
    }

    final boundedBytes = await readResponse().timeout(
      const Duration(seconds: 15),
    );
    final text = utf8.decode(boundedBytes, allowMalformed: false);
    final dynamic decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic> || decoded['jsonrpc'] != '2.0') {
      throw const McpException(
        'MCP response was not a valid JSON-RPC 2.0 object.',
      );
    }
    final safeDecoded = Map<String, dynamic>.from(
      _redactMcpSecret(decoded, token) as Map,
    );
    if (notification) {
      throw const McpException(
        'MCP server returned a response to a notification.',
      );
    }
    if (safeDecoded.containsKey('result') == safeDecoded.containsKey('error')) {
      throw const McpException(
        'MCP response must contain exactly one result or error.',
      );
    }
    return safeDecoded;
  }
}

Object? _redactMcpSecret(Object? value, String token) {
  if (token.isEmpty) return value;
  if (value is String) return value.replaceAll(token, '[redacted]');
  if (value is List) {
    return value.map((item) => _redactMcpSecret(item, token)).toList();
  }
  if (value is Map) {
    return value.map((key, item) {
      final safeKey = key is String ? key.replaceAll(token, '[redacted]') : key;
      return MapEntry(safeKey, _redactMcpSecret(item, token));
    });
  }
  return value;
}
