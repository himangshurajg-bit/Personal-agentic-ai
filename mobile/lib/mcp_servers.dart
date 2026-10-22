import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class McpServer {
  final String id;
  final String name;
  final String endpoint;
  const McpServer({required this.id, required this.name, required this.endpoint});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'endpoint': endpoint};
  factory McpServer.fromJson(Map<String, dynamic> value) => McpServer(
    id: value['id'] as String,
    name: value['name'] as String,
    endpoint: value['endpoint'] as String,
  );
}

class McpToolInfo {
  final String name;
  final String description;
  const McpToolInfo(this.name, this.description);
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
  if (value.isEmpty || value.length > 2048 || uri == null ||
      !uri.hasAuthority || uri.host.isEmpty || uri.userInfo.isNotEmpty ||
      uri.hasQuery || uri.hasFragment ||
      !['https', 'http'].contains(uri.scheme) ||
      (uri.scheme == 'http' &&
          !const ['localhost', '127.0.0.1', '::1', '10.0.2.2'].contains(uri.host))) {
    throw const McpException(
      'Use an HTTPS MCP endpoint. Plain HTTP is allowed only for localhost or the Android emulator.',
    );
  }
  return uri;
}

void validateMcpServer(String name, String endpoint) {
  final normalized = name.trim();
  if (normalized.isEmpty || normalized.runes.length > 48 ||
      normalized.contains(RegExp(r'[\x00-\x1f]'))) {
    throw const McpException('Server name must be 1–48 characters without control characters.');
  }
  validateMcpEndpoint(endpoint);
}

/// Stores endpoint metadata and keeps optional bearer credentials in a separate secure key.
/// Discovered MCP tools are displayed only: this client deliberately has no tools/call method.
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
      if (item is! Map) throw const McpException('Saved MCP server entry is invalid.');
      final server = McpServer.fromJson(Map<String, dynamic>.from(item));
      validateMcpServer(server.name, server.endpoint);
      if (!RegExp(r'^mcp-[A-Za-z0-9-]{1,60}$').hasMatch(server.id) ||
          !ids.add(server.id) || !names.add(server.name.trim().toLowerCase())) {
        throw const McpException('Saved MCP server identifier or name is invalid.');
      }
      result.add(server);
    }
    return result;
  }

  Future<List<McpServer>> save(List<McpServer> servers) async {
    if (servers.length > 25) throw const McpException('You can add up to 25 MCP servers.');
    final ids = <String>{};
    final names = <String>{};
    for (final server in servers) {
      validateMcpServer(server.name, server.endpoint);
      if (!RegExp(r'^mcp-[A-Za-z0-9-]{1,60}$').hasMatch(server.id) ||
          !ids.add(server.id) || !names.add(server.name.trim().toLowerCase())) {
        throw const McpException('Server IDs and names must be unique.');
      }
    }
    await storage.write(key: 'custom_mcp_servers_v1', value: jsonEncode(servers.map((s) => s.toJson()).toList()));
    return List.unmodifiable(servers);
  }

  Future<void> setBearerToken(String id, String token) async {
    final validToken = RegExp(r'^[A-Za-z0-9\-._~+/]+=*$');
    if (!RegExp(r'^mcp-[A-Za-z0-9-]{1,60}$').hasMatch(id) ||
        token.length > 4096 || (token.isNotEmpty && !validToken.hasMatch(token))) {
      throw const McpException('Use a valid bearer token without spaces or line breaks.');
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

  Future<List<McpToolInfo>> discoverTools(McpServer server) async {
    validateMcpServer(server.name, server.endpoint);
    final token = await storage.read(key: 'custom_mcp_token_${server.id}') ?? '';
    final client = clientFactory();
    var requestId = 0;
    String? sessionId;
    Future<Map<String, dynamic>?> post(String method, Map<String, dynamic>? params, {bool notification = false}) async {
      final body = <String, dynamic>{'jsonrpc': '2.0', 'method': method};
      if (!notification) body['id'] = ++requestId;
      if (params != null) body['params'] = params;
      final request = http.Request('POST', validateMcpEndpoint(server.endpoint))
        ..followRedirects = false
        ..headers.addAll({
          'Content-Type': 'application/json',
          'Accept': 'application/json, text/event-stream',
          if (method != 'initialize') 'MCP-Protocol-Version': protocolVersion,
          if (sessionId != null) 'Mcp-Session-Id': sessionId!,
          if (token.isNotEmpty) 'Authorization': 'Bearer $token',
        })
        ..body = jsonEncode(body);
      final response = await client.send(request).timeout(const Duration(seconds: 12));
      final returnedSession = response.headers['mcp-session-id'];
      if (returnedSession != null) {
        if (returnedSession.isEmpty || returnedSession.length > 256 || returnedSession.contains(RegExp(r'[\r\n]'))) {
          throw const McpException('MCP server returned an invalid session identifier.');
        }
        sessionId = returnedSession;
      }
      if (notification && response.statusCode == 202) return null;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw McpException('MCP server returned HTTP ${response.statusCode}.');
      }
      final contentType = response.headers['content-type'] ?? '';
      if (!contentType.toLowerCase().contains('application/json')) {
        throw const McpException('This build supports bounded JSON MCP responses, not SSE streams.');
      }
      final bytes = <int>[];
      Future<List<int>> readResponse() async {
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > 256 * 1024) {
            throw const McpException('MCP response exceeded the 256 KB safety limit.');
          }
          bytes.addAll(chunk);
        }
        return bytes;
      }
      final boundedBytes = await readResponse().timeout(const Duration(seconds: 15));
      final text = utf8.decode(boundedBytes, allowMalformed: false);
      final dynamic decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) throw const McpException('MCP response was not a JSON-RPC object.');
      if (decoded['error'] != null) throw const McpException('MCP server rejected the protocol request.');
      if (decoded['id'] != body['id'] && !notification) throw const McpException('MCP response ID did not match the request.');
      final result = decoded['result'];
      return result is Map<String, dynamic> ? result : <String, dynamic>{};
    }

    try {
      final initialized = await post('initialize', {
        'protocolVersion': protocolVersion,
        'capabilities': <String, dynamic>{},
        'clientInfo': {'name': 'Personal Agentic AI', 'version': '0.3.0'},
      });
      if (initialized == null || initialized['protocolVersion'] != protocolVersion) {
        throw const McpException('MCP server did not negotiate the supported protocol version.');
      }
      await post('notifications/initialized', null, notification: true);
      final tools = <McpToolInfo>[];
      final cursors = <String>{};
      String? cursor;
      for (var page = 0; page < 5; page++) {
        final params = <String, dynamic>{};
        if (cursor != null) params['cursor'] = cursor;
        final result = await post('tools/list', params);
        final rawTools = result?['tools'];
        if (rawTools is! List || tools.length + rawTools.length > 200) {
          throw const McpException('MCP tools/list response is invalid or exceeds 200 tools.');
        }
        for (final item in rawTools) {
          if (item is! Map || item['name'] is! String ||
              (item['name'] as String).isEmpty ||
              (item['name'] as String).length > 128) {
            throw const McpException('MCP server returned an invalid tool description.');
          }
          final description = item['description'] is String
              ? item['description'] as String
              : '';
          tools.add(McpToolInfo(
            item['name'] as String,
            description.length <= 500
                ? description
                : '${description.substring(0, 500)}…',
          ));
        }
        final next = result?['nextCursor'];
        if (next == null) return List.unmodifiable(tools);
        if (next is! String || next.isEmpty || next.length > 1024 || !cursors.add(next)) {
          throw const McpException('MCP server returned an invalid pagination cursor.');
        }
        cursor = next;
      }
      throw const McpException('MCP server has more than five pages of tools; discovery stopped safely.');
    } on TimeoutException {
      throw const McpException('MCP server timed out. Nothing was retried.');
    } on FormatException {
      throw const McpException('MCP server returned invalid JSON.');
    } on http.ClientException {
      throw const McpException('Could not reach the MCP server. Check its URL and connection.');
    } on McpException {
      rethrow;
    } catch (_) {
      throw const McpException('MCP connection or response could not be verified.');
    } finally {
      client.close();
    }
  }
}
