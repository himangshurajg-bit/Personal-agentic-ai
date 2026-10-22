import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'google_sign_in_setup.dart';

/// User-triggered Google Sheets actions restricted to spreadsheets created by
/// this app under Google's per-file drive.file scope.
class GoogleSheetsConnector {
  GoogleSheetsConnector({
    GoogleSheetsSecretStore? storage,
    http.Client Function()? clientFactory,
    GoogleSheetsAuthorizer? authorizer,
    DateTime Function()? now,
  }) : _storage = storage ?? FlutterSecureSheetsSecretStore(),
       _clientFactory = clientFactory ?? http.Client.new,
       _authorizer = authorizer ?? GoogleSheetsGoogleSignInAuthorizer(),
       _now = now ?? DateTime.now;

  static const String fileScope = 'https://www.googleapis.com/auth/drive.file';
  static const String _sheetsRoot = 'https://sheets.googleapis.com/v4';
  static const String _driveRoot = 'https://www.googleapis.com/drive/v3';
  static const String _tokenKey = 'google_sheets_access_token';
  static const String _savedAtKey = 'google_sheets_token_saved_at';
  static const String _emailKey = 'google_sheets_email';
  static const Duration _tokenLifetime = Duration(minutes: 55);
  static const int maxSpreadsheetsPerLoad = 25;
  static const int maxRows = 50;
  static const int maxColumns = 10;
  static const int maxCells = 500;
  static const int maxTsvBytes = 32 * 1024;
  static const String spreadsheetMimeType =
      'application/vnd.google-apps.spreadsheet';
  static const String _appPropertyKey = 'personalAssistantSheet';
  static const String _appPropertyValue = '1';

  final GoogleSheetsSecretStore _storage;
  final http.Client Function() _clientFactory;
  final GoogleSheetsAuthorizer _authorizer;
  final DateTime Function() _now;
  final Set<String> _selectedOrCreatedIds = <String>{};
  final Map<String, List<GoogleSheetTab>> _tabsBySpreadsheet = {};

  Future<String?> get connectedEmail async {
    final email = await _storage.read(key: _emailKey);
    final token = await _storage.read(key: _tokenKey);
    final savedAt = int.tryParse(await _storage.read(key: _savedAtKey) ?? '');
    if (email == null || token == null || savedAt == null) return null;
    final age = _now().difference(DateTime.fromMillisecondsSinceEpoch(savedAt));
    if (age.isNegative || age >= _tokenLifetime) {
      await _clearCredentials();
      _clearSelection();
      return null;
    }
    return email;
  }

  /// Requests Google's recommended per-file grant only after Connect is tapped.
  Future<void> connect() async {
    final credentials = await _authorizer.authorize([fileScope]);
    if (credentials.email.isEmpty || credentials.accessToken.isEmpty) {
      throw const GoogleSheetsException(
        'Google did not return an account and access token. Nothing was connected.',
      );
    }
    try {
      await _storage.write(
        key: _savedAtKey,
        value: _now().millisecondsSinceEpoch.toString(),
      );
      await _storage.write(key: _emailKey, value: credentials.email);
      await _storage.write(key: _tokenKey, value: credentials.accessToken);
    } catch (_) {
      await _clearCredentials();
      rethrow;
    }
  }

  /// Removes only this connector's token copy; Drive/Docs grants remain intact.
  Future<void> disconnect() async {
    _clearSelection();
    await _clearCredentials();
  }

  /// Lists only app-tagged spreadsheets; it never enumerates the user's Drive.
  Future<List<GoogleSheetFile>> listCreatedSpreadsheets() async {
    final uri = Uri.parse('$_driveRoot/files').replace(
      queryParameters: {
        'q':
            "mimeType = '$spreadsheetMimeType' and appProperties has { key='$_appPropertyKey' and value='$_appPropertyValue' } and trashed = false",
        'pageSize': '$maxSpreadsheetsPerLoad',
        'orderBy': 'modifiedTime desc',
        'fields': 'files(id,name,mimeType,modifiedTime,appProperties)',
      },
    );
    final json = await _requestJson('GET', uri);
    final files = ((json['files'] as List?) ?? const [])
        .whereType<Map>()
        .map((raw) => GoogleSheetFile.fromJson(Map<String, dynamic>.from(raw)))
        .where((file) => file.id.isNotEmpty && file.title.isNotEmpty)
        .toList(growable: false);
    _selectedOrCreatedIds
      ..clear()
      ..addAll(files.map((file) => file.id));
    _tabsBySpreadsheet.clear();
    return files;
  }

  /// Creates one blank spreadsheet and app-tags it, so later lists remain
  /// constrained to files this app created. If tagging fails, creation may
  /// already have succeeded; callers must inspect Drive before retrying.
  Future<GoogleSheetFile> createSpreadsheet(String title) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty || cleanTitle.length > 120) {
      throw const GoogleSheetsException(
        'Choose a spreadsheet title from 1 to 120 characters.',
      );
    }
    final uri = Uri.parse('$_sheetsRoot/spreadsheets');
    final created = await _requestJson(
      'POST',
      uri,
      body: {
        'properties': {'title': cleanTitle},
      },
      uncertainWriteMessage: 'The spreadsheet may have been created. Check Drive before retrying spreadsheet creation.',
    );
    final id = created['spreadsheetId'];
    final props = created['properties'];
    final name = props is Map && props['title'] is String
        ? props['title'] as String
        : cleanTitle;
    if (id is! String || id.isEmpty) {
      throw const GoogleSheetsException(
        'Google did not return a spreadsheet ID. Check Drive before retrying creation.',
      );
    }
    try {
      await _requestJson(
        'PATCH',
        Uri.parse('$_driveRoot/files/${Uri.encodeComponent(id)}').replace(
          queryParameters: {
            'fields': 'id,name,mimeType,modifiedTime,appProperties',
          },
        ),
        body: {
          'appProperties': {_appPropertyKey: _appPropertyValue},
        },
        uncertainWriteMessage: 'The spreadsheet may exist but its app-only label is unconfirmed. Check Drive before retrying creation.',
      );
    } catch (_) {
      throw const GoogleSheetsException(
        'The spreadsheet may already exist, but its app-only label was not confirmed. Check Drive before retrying creation.',
      );
    }
    _selectedOrCreatedIds.add(id);
    final tabs = _parseTabs(created);
    if (tabs.isNotEmpty) _tabsBySpreadsheet[id] = tabs;
    return GoogleSheetFile(id: id, title: name, tabs: tabs);
  }

  /// Opens metadata only after the user selects an app-created spreadsheet.
  Future<GoogleSheetFile> openSelectedSpreadsheet(String spreadsheetId) async {
    _requireSelected(spreadsheetId);
    final uri =
        Uri.parse(
          '$_sheetsRoot/spreadsheets/${Uri.encodeComponent(spreadsheetId)}',
        ).replace(
          queryParameters: {
            'includeGridData': 'false',
            'fields': 'spreadsheetId,properties(title),sheets(properties(sheetId,title,gridProperties(rowCount,columnCount)))',
          },
        );
    final json = await _requestJson('GET', uri);
    final id = json['spreadsheetId'] is String
        ? json['spreadsheetId'] as String
        : spreadsheetId;
    if (id != spreadsheetId) {
      throw const GoogleSheetsException(
        'Google returned a different spreadsheet than the one selected.',
      );
    }
    final props = json['properties'];
    final title = props is Map && props['title'] is String
        ? props['title'] as String
        : 'Untitled spreadsheet';
    final tabs = _parseTabs(json);
    if (tabs.isEmpty) {
      throw const GoogleSheetsException(
        'This spreadsheet has no readable tabs.',
      );
    }
    _tabsBySpreadsheet[id] = tabs;
    return GoogleSheetFile(id: id, title: title, tabs: tabs);
  }

  /// Reads only an explicit, bounded A1 range in a selected tab.
  Future<GoogleSheetRange> readRange({
    required String spreadsheetId,
    required String sheetTitle,
    required String range,
  }) async {
    final safeRange = _validateRange(range);
    final tab = _requireTab(spreadsheetId, sheetTitle);
    final qualified = _qualifiedRange(tab.title, safeRange.range);
    final uri = Uri.parse(
      '$_sheetsRoot/spreadsheets/${Uri.encodeComponent(spreadsheetId)}/values/${Uri.encodeComponent(qualified)}',
    ).replace(queryParameters: {'valueRenderOption': 'FORMATTED_VALUE'});
    final json = await _requestJson('GET', uri);
    final rows = _parseValues(json['values']);
    if (rows.length > safeRange.rows ||
        rows.any((row) => row.length > safeRange.columns)) {
      throw const GoogleSheetsException(
        'Google returned more cells than the selected range allows.',
      );
    }
    return GoogleSheetRange(
      spreadsheetId: spreadsheetId,
      sheetTitle: tab.title,
      range: safeRange.range,
      rows: rows,
    );
  }

  /// Writes a rectangular TSV into exactly the visible bounded range, using
  /// RAW input so cell text beginning with '=' is never interpreted as a formula.
  Future<void> writeRange({
    required String spreadsheetId,
    required String sheetTitle,
    required String range,
    required String tabSeparatedValues,
  }) async {
    final safeRange = _validateRange(range);
    final tab = _requireTab(spreadsheetId, sheetTitle);
    final bytes = utf8.encode(tabSeparatedValues);
    if (bytes.isEmpty || bytes.length > maxTsvBytes) {
      throw const GoogleSheetsException(
        'Enter between 1 byte and 32 KB of cell values before saving.',
      );
    }
    final rows = tabSeparatedValues
        .split('\n')
        .map((line) {
          final normalized = line.endsWith('\r')
              ? line.substring(0, line.length - 1)
              : line;
          return normalized.split('\t');
        })
        .toList(growable: false);
    if (rows.length != safeRange.rows ||
        rows.any((row) => row.length != safeRange.columns)) {
      throw const GoogleSheetsException(
        'The tab-separated values must exactly match the selected range dimensions.',
      );
    }
    if (rows.expand((row) => row).any((cell) => cell.length > 2000)) {
      throw const GoogleSheetsException(
        'Each cell must be 2,000 characters or less.',
      );
    }
    final qualified = _qualifiedRange(tab.title, safeRange.range);
    final uri =
        Uri.parse(
          '$_sheetsRoot/spreadsheets/${Uri.encodeComponent(spreadsheetId)}/values/${Uri.encodeComponent(qualified)}',
        ).replace(
          queryParameters: {
            'valueInputOption': 'RAW',
            'includeValuesInResponse': 'true',
            'responseValueRenderOption': 'FORMATTED_VALUE',
          },
        );
    await _requestJson(
      'PUT',
      uri,
      body: {'majorDimension': 'ROWS', 'values': rows},
      uncertainWriteMessage: 'The cell update may have completed. Read this range before trying the write again; it was not retried.',
    );
  }

  _ValidatedRange _validateRange(String input) {
    final match = RegExp(
      r'^([A-Z]{1,2})([1-9][0-9]*):([A-Z]{1,2})([1-9][0-9]*)$',
    ).firstMatch(input.trim());
    if (match == null) {
      throw const GoogleSheetsException(
        'Use one explicit range such as A1:C4. Single cells and open-ended ranges are not supported.',
      );
    }
    final startCol = _columnNumber(match.group(1)!);
    final startRow = int.parse(match.group(2)!);
    final endCol = _columnNumber(match.group(3)!);
    final endRow = int.parse(match.group(4)!);
    if (startRow > endRow || startCol > endCol) {
      throw const GoogleSheetsException('The range end must follow its start.');
    }
    final rows = endRow - startRow + 1;
    final columns = endCol - startCol + 1;
    if (endRow > maxRows || endCol > maxColumns || rows * columns > maxCells) {
      throw const GoogleSheetsException(
        'Keep the range within rows 1–50, columns A–J, and 500 cells.',
      );
    }
    return _ValidatedRange(input.trim(), rows, columns);
  }

  int _columnNumber(String letters) {
    var result = 0;
    for (final rune in letters.codeUnits) {
      result = result * 26 + rune - 64;
    }
    return result;
  }

  String _qualifiedRange(String title, String range) =>
      "'${title.replaceAll("'", "''")}'!$range";

  List<List<String>> _parseValues(Object? raw) {
    if (raw == null) return const [];
    if (raw is! List || raw.length > maxRows) {
      throw const GoogleSheetsException(
        'Google returned an invalid or oversized cell range.',
      );
    }
    final output = <List<String>>[];
    for (final row in raw) {
      if (row is! List || row.length > maxColumns) {
        throw const GoogleSheetsException(
          'Google returned an invalid or oversized cell range.',
        );
      }
      output.add(row.map((value) => value.toString()).toList());
    }
    return output;
  }

  List<GoogleSheetTab> _parseTabs(Map<String, dynamic> json) {
    final rawSheets = json['sheets'];
    if (rawSheets is! List) return const [];
    return rawSheets
        .whereType<Map>()
        .map((raw) {
          final properties = raw['properties'];
          if (properties is! Map) return null;
          final title = properties['title'];
          final id = properties['sheetId'];
          if (title is! String || title.isEmpty || id is! num) return null;
          final grid = properties['gridProperties'];
          final rowCount = grid is Map && grid['rowCount'] is num
              ? (grid['rowCount'] as num).toInt()
              : 0;
          final columnCount = grid is Map && grid['columnCount'] is num
              ? (grid['columnCount'] as num).toInt()
              : 0;
          return GoogleSheetTab(
            id: id.toInt(),
            title: title,
            rowCount: rowCount,
            columnCount: columnCount,
          );
        })
        .whereType<GoogleSheetTab>()
        .toList(growable: false);
  }

  GoogleSheetTab _requireTab(String spreadsheetId, String title) {
    _requireSelected(spreadsheetId);
    final tab = _tabsBySpreadsheet[spreadsheetId]
        ?.where((item) => item.title == title)
        .firstOrNull;
    if (tab == null) {
      throw const GoogleSheetsException(
        'Open a spreadsheet and choose one of its tabs before reading or writing.',
      );
    }
    return tab;
  }

  void _requireSelected(String id) {
    if (id.isEmpty || !_selectedOrCreatedIds.contains(id)) {
      throw const GoogleSheetsException(
        'Load this app’s spreadsheets and choose one first.',
      );
    }
  }

  void _clearSelection() {
    _selectedOrCreatedIds.clear();
    _tabsBySpreadsheet.clear();
  }

  Future<Map<String, dynamic>> _requestJson(
    String method,
    Uri uri, {
    Map<String, Object?>? body,
    String? uncertainWriteMessage,
  }) async {
    final response = await _requestBytes(
      method,
      uri,
      body: body == null ? null : utf8.encode(jsonEncode(body)),
      headers: body == null
          ? const {}
          : const {'Content-Type': 'application/json; charset=utf-8'},
      uncertainWriteMessage: uncertainWriteMessage,
    );
    if (response.bodyBytes.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Do not leak provider responses into the UI.
    }
    throw const GoogleSheetsException(
      'Google Sheets returned an unexpected response.',
    );
  }

  Future<http.Response> _requestBytes(
    String method,
    Uri uri, {
    List<int>? body,
    Map<String, String> headers = const {},
    String? uncertainWriteMessage,
  }) async {
    final token = await _usableToken();
    final client = _clientFactory();
    try {
      final request = http.Request(method, uri)
        ..followRedirects = false
        ..headers.addAll({
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          ...headers,
        });
      if (body != null) request.bodyBytes = body;
      final streamed = await client
          .send(request)
          .timeout(const Duration(seconds: 20));
      final response = await http.Response.fromStream(streamed)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 401) {
        await _clearCredentials();
        _clearSelection();
        throw const GoogleSheetsException(
          'Google Sheets access expired or was revoked. Reconnect to continue; no request was retried.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw GoogleSheetsException(
          'Google Sheets returned HTTP ${response.statusCode}. Check Sheets/Drive API setup and file access; no request was retried.',
        );
      }
      return response;
    } on GoogleSheetsException {
      rethrow;
    } catch (_) {
      throw GoogleSheetsException(
        uncertainWriteMessage ?? 'Google Sheets could not be reached. Check your connection; no request was retried.',
      );
    } finally {
      client.close();
    }
  }

  Future<String> _usableToken() async {
    final token = await _storage.read(key: _tokenKey);
    final savedAt = int.tryParse(await _storage.read(key: _savedAtKey) ?? '');
    if (token == null || token.isEmpty || savedAt == null) {
      throw const GoogleSheetsException('Connect Google Sheets first.');
    }
    final age = _now().difference(DateTime.fromMillisecondsSinceEpoch(savedAt));
    if (age.isNegative || age >= _tokenLifetime) {
      await _clearCredentials();
      _clearSelection();
      throw const GoogleSheetsException(
        'Google Sheets access expired. Reconnect from this screen; no request was sent.',
      );
    }
    return token;
  }

  Future<void> _clearCredentials() async => Future.wait([
    _storage.delete(key: _tokenKey),
    _storage.delete(key: _savedAtKey),
    _storage.delete(key: _emailKey),
  ]);
}

class GoogleSheetsGoogleSignInAuthorizer implements GoogleSheetsAuthorizer {
  GoogleSheetsGoogleSignInAuthorizer({String? serverClientId})
    : serverClientId =
          serverClientId ??
          const String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  final String serverClientId;

  @override
  Future<GoogleSheetsCredentials> authorize(List<String> scopes) async {
    if (serverClientId.trim().isEmpty) {
      throw const GoogleSheetsException(
        'Google Sheets is not configured yet. Add the Google OAuth Web client ID and Android signing SHA-1 described in the setup guide.',
      );
    }
    try {
      await GoogleSignInSetup.initialize(serverClientId.trim());
      final user = await GoogleSignIn.instance.authenticate();
      final authorization = await user.authorizationClient.authorizeScopes(
        scopes,
      );
      return GoogleSheetsCredentials(
        email: user.email,
        accessToken: authorization.accessToken,
      );
    } on GoogleSignInException catch (error) {
      throw GoogleSheetsException(
        error.code == GoogleSignInExceptionCode.canceled
            ? 'Google sign-in was canceled. Nothing was connected.'
            : 'Google sign-in failed (${error.code.name}). Check OAuth setup and try again.',
      );
    } catch (_) {
      throw const GoogleSheetsException(
        'Google sign-in could not finish. Check OAuth client, Android package/SHA-1, and Sheets/Drive API setup.',
      );
    }
  }
}

abstract interface class GoogleSheetsSecretStore {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String value});
  Future<void> delete({required String key});
}

class FlutterSecureSheetsSecretStore implements GoogleSheetsSecretStore {
  FlutterSecureSheetsSecretStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  @override
  Future<String?> read({required String key}) => _storage.read(key: key);
  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}

abstract interface class GoogleSheetsAuthorizer {
  Future<GoogleSheetsCredentials> authorize(List<String> scopes);
}

class GoogleSheetsCredentials {
  const GoogleSheetsCredentials({
    required this.email,
    required this.accessToken,
  });
  final String email;
  final String accessToken;
}

class GoogleSheetFile {
  const GoogleSheetFile({
    required this.id,
    required this.title,
    this.tabs = const [],
    this.modifiedTime,
  });
  final String id;
  final String title;
  final List<GoogleSheetTab> tabs;
  final DateTime? modifiedTime;

  factory GoogleSheetFile.fromJson(Map<String, dynamic> json) =>
      GoogleSheetFile(
        id: json['id'] is String ? json['id'] as String : '',
        title: json['name'] is String ? json['name'] as String : '',
        modifiedTime: json['modifiedTime'] is String
            ? DateTime.tryParse(json['modifiedTime'] as String)
            : null,
      );
}

class GoogleSheetTab {
  const GoogleSheetTab({
    required this.id,
    required this.title,
    required this.rowCount,
    required this.columnCount,
  });
  final int id;
  final String title;
  final int rowCount;
  final int columnCount;
}

class GoogleSheetRange {
  const GoogleSheetRange({
    required this.spreadsheetId,
    required this.sheetTitle,
    required this.range,
    required this.rows,
  });
  final String spreadsheetId;
  final String sheetTitle;
  final String range;
  final List<List<String>> rows;
}

class GoogleSheetsException implements Exception {
  const GoogleSheetsException(this.message);
  final String message;
  @override
  String toString() => message;
}

class _ValidatedRange {
  const _ValidatedRange(this.range, this.rows, this.columns);
  final String range;
  final int rows;
  final int columns;
}
