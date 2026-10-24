import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

const appReleaseApiUrl =
    'https://api.github.com/repos/himangshurajg-bit/Personal-agentic-ai/releases/latest';
const appReleasePageBase =
    'https://github.com/himangshurajg-bit/Personal-agentic-ai/releases/tag/';
const appReleaseDownloadBase =
    'https://github.com/himangshurajg-bit/Personal-agentic-ai/releases/download/';
const appReleaseApkName = 'app-release.apk';
const appReleaseMaxBytes = 250 * 1024 * 1024;

class InstalledAppVersion {
  const InstalledAppVersion({
    required this.packageName,
    required this.versionName,
    required this.versionCode,
  });

  final String packageName;
  final String versionName;
  final int versionCode;

  factory InstalledAppVersion.fromMap(Map<String, dynamic> value) {
    final packageName = value['packageName'];
    final versionName = value['versionName'];
    final versionCode = value['versionCode'];
    if (packageName != 'dev.personalagent.personal_assistant' ||
        versionName is! String ||
        versionName.isEmpty ||
        versionCode is! int ||
        versionCode < 1) {
      throw const FormatException('Installed app version is unavailable.');
    }
    return InstalledAppVersion(
      packageName: packageName as String,
      versionName: versionName,
      versionCode: versionCode,
    );
  }
}

class AppRelease {
  const AppRelease({
    required this.tag,
    required this.versionName,
    required this.buildNumber,
    required this.title,
    required this.notes,
    required this.releasePage,
    required this.apkDownload,
    required this.apkSize,
  });

  final String tag;
  final String versionName;
  final int buildNumber;
  final String title;
  final String notes;
  final Uri releasePage;
  final Uri apkDownload;
  final int apkSize;

  factory AppRelease.fromJson(Map<String, dynamic> json) {
    if (json['draft'] != false || json['prerelease'] != false) {
      throw const FormatException(
        'The latest release is not a stable release.',
      );
    }
    final tag = json['tag_name'];
    if (tag is! String) {
      throw const FormatException('Release tag is missing.');
    }
    final match = RegExp(r'^v([0-9]+(?:\.[0-9]+){2,4})-build([1-9][0-9]*)$')
        .firstMatch(tag);
    if (match == null) {
      throw const FormatException('Release tag format is not supported.');
    }
    final versionName = match.group(1)!;
    final buildNumber = int.tryParse(match.group(2)!);
    if (buildNumber == null || buildNumber < 1) {
      throw const FormatException('Release build number is invalid.');
    }

    final page = _checkedUri(
      json['html_url'],
      expected: Uri.parse('$appReleasePageBase$tag'),
    );
    final rawAssets = json['assets'];
    if (rawAssets is! List) {
      throw const FormatException('Release APK asset is missing.');
    }
    final matches = rawAssets
        .where((asset) {
          return asset is Map && asset['name'] == appReleaseApkName;
        })
        .toList(growable: false);
    if (matches.length != 1 || matches.single is! Map) {
      throw const FormatException(
        'Release must contain one official APK asset.',
      );
    }
    final asset = Map<String, dynamic>.from(matches.single as Map);
    if (asset['state'] != 'uploaded') {
      throw const FormatException('Release APK is not fully published.');
    }
    final contentType = asset['content_type'];
    if (contentType != 'application/vnd.android.package-archive' &&
        contentType != 'application/octet-stream') {
      throw const FormatException('Release asset is not an APK.');
    }
    final size = asset['size'];
    if (size is! int || size < 1024 * 1024 || size > appReleaseMaxBytes) {
      throw const FormatException(
        'Release APK size is outside the safe limit.',
      );
    }
    final download = _checkedUri(
      asset['browser_download_url'],
      expected: Uri.parse('$appReleaseDownloadBase$tag/$appReleaseApkName'),
    );
    final digest = asset['digest'];
    if (digest != null &&
        (digest is! String ||
            !RegExp(r'^sha256:[0-9a-fA-F]{64}$').hasMatch(digest))) {
      throw const FormatException('Release APK digest is malformed.');
    }

    final title = json['name'];
    final body = json['body'];
    if (title is! String || title.trim().isEmpty || body is! String) {
      throw const FormatException('Release title or notes are missing.');
    }
    final cleanTitle = title.trim();
    final cleanNotes = body.trim();
    return AppRelease(
      tag: tag,
      versionName: versionName,
      buildNumber: buildNumber,
      title: cleanTitle.length > 120
          ? cleanTitle.substring(0, 120)
          : cleanTitle,
      notes: cleanNotes.length > 4000
          ? cleanNotes.substring(0, 4000)
          : cleanNotes,
      releasePage: page,
      apkDownload: download,
      apkSize: size,
    );
  }
}

Uri _checkedUri(Object? raw, {required Uri expected}) {
  if (raw is! String) {
    throw const FormatException('Release link is missing.');
  }
  final uri = Uri.tryParse(raw);
  if (uri == null ||
      raw != expected.toString() ||
      uri.scheme != 'https' ||
      uri.host != 'github.com' ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw const FormatException('Release link is not the pinned GitHub asset.');
  }
  return uri;
}

List<int>? _numericVersion(String value) {
  if (!RegExp(r'^\d+(?:\.\d+){2,4}$').hasMatch(value)) return null;
  final parts = <int>[];
  for (final part in value.split('.')) {
    final parsed = int.tryParse(part);
    if (parsed == null) return null;
    parts.add(parsed);
  }
  return parts;
}

int compareNumericVersions(String left, String right) {
  final a = _numericVersion(left);
  final b = _numericVersion(right);
  if (a == null || b == null) {
    throw const FormatException('Version number format is not supported.');
  }
  final length = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < length; i++) {
    final av = i < a.length ? a[i] : 0;
    final bv = i < b.length ? b[i] : 0;
    if (av != bv) return av.compareTo(bv);
  }
  return 0;
}

bool isReleaseNewer(AppRelease release, InstalledAppVersion installed) {
  final versionOrder = compareNumericVersions(
    release.versionName,
    installed.versionName,
  );
  if (versionOrder != 0) return versionOrder > 0;
  return release.buildNumber > installed.versionCode;
}

class AppReleaseService {
  AppReleaseService({
    http.Client? client,
    this._requestTimeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration _requestTimeout;

  Future<AppRelease> fetchLatest() async {
    final deadline = DateTime.now().add(_requestTimeout);
    final request = http.Request('GET', Uri.parse(appReleaseApiUrl))
      ..followRedirects = false
      ..headers.addAll(const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      });
    late final http.StreamedResponse streamed;
    try {
      streamed = await _client.send(request).timeout(_requestTimeout);
    } on TimeoutException {
      throw StateError('GitHub release check timed out.');
    }
    if (streamed.statusCode != 200) {
      throw StateError(
        'GitHub release check failed (HTTP ${streamed.statusCode}).',
      );
    }
    if (streamed.contentLength != null &&
        streamed.contentLength! > 1024 * 1024) {
      await streamed.stream.listen((_) {}).cancel();
      throw const FormatException(
        'GitHub release response exceeded the size limit.',
      );
    }

    final bytes = <int>[];
    try {
      await for (final chunk in streamed.stream.timeout(_requestTimeout)) {
        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException('GitHub release check timed out.');
        }
        if (bytes.length + chunk.length > 1024 * 1024) {
          throw const FormatException(
            'GitHub release response exceeded the size limit.',
          );
        }
        bytes.addAll(chunk);
      }
    } on TimeoutException {
      throw StateError('GitHub release check timed out.');
    }

    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('GitHub returned an invalid release record.');
    }
    return AppRelease.fromJson(decoded);
  }

  void close() => _client.close();
}

class AppUpdatePanel extends StatefulWidget {
  const AppUpdatePanel({super.key, this.service, this.platform});

  final AppReleaseService? service;
  final MethodChannel? platform;

  @override
  State<AppUpdatePanel> createState() => _AppUpdatePanelState();
}

class _AppUpdatePanelState extends State<AppUpdatePanel> {
  static const _defaultPlatform = MethodChannel(
    'personal_assistant/app_update',
  );
  late final AppReleaseService _service = widget.service ?? AppReleaseService();
  late final bool _ownsService = widget.service == null;
  AppRelease? _release;
  InstalledAppVersion? _installed;
  String? _error;
  bool _checking = false;
  bool _opening = false;
  bool? _available;
  bool _handoffOpened = false;

  MethodChannel get _platform => widget.platform ?? _defaultPlatform;

  Future<void> _check() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _error = null;
      _available = null;
      _release = null;
      _handoffOpened = false;
    });
    try {
      final versionMap = await _platform.invokeMapMethod<String, dynamic>(
        'get_installed_version',
      );
      if (versionMap == null) {
        throw const FormatException('Installed app version is unavailable.');
      }
      final installed = InstalledAppVersion.fromMap(versionMap);
      final latest = await _service.fetchLatest();
      final available = isReleaseNewer(latest, installed);
      if (!mounted) return;
      setState(() {
        _installed = installed;
        _release = latest;
        _available = available;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _userFacingError(error));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  String _userFacingError(Object error) {
    if (error is FormatException) return error.message;
    if (error is StateError) return error.message;
    return 'Could not check GitHub releases. Check your connection and try again.';
  }

  Future<void> _openOfficialDownload() async {
    final release = _release;
    if (release == null || _available != true || _opening) return;
    setState(() {
      _opening = true;
      _error = null;
      _handoffOpened = false;
    });
    try {
      await _platform.invokeMethod<void>('open_official_release_download', {
        'url': release.apkDownload.toString(),
      });
      if (!mounted) return;
      setState(() => _handoffOpened = true);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error is PlatformException && error.message != null
            ? error.message!
            : 'The official GitHub download could not be opened.',
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  void dispose() {
    if (_ownsService) _service.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Manually check the app’s official GitHub release. The app does not install updates itself; Android handles the final install confirmation.',
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          key: const Key('check-app-update'),
          onPressed: _checking ? null : _check,
          icon: _checking
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.system_update_alt_rounded),
          label: Text(_checking ? 'Checking…' : 'Check for updates'),
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 8),
        Text(_error!, key: const Key('app-update-error')),
      ],
      if (_release != null && _available != null) ...[
        const SizedBox(height: 12),
        Text(
          'Installed: ${_installed!.versionName} · build ${_installed!.versionCode}',
        ),
        const SizedBox(height: 8),
        Text(
          _available! ? 'Update available' : 'You’re up to date',
          key: const Key('app-update-status'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          '${_release!.title} · ${_release!.versionName} build ${_release!.buildNumber}',
        ),
        if (_release!.notes.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(_release!.notes, key: const Key('app-update-notes')),
        ],
        if (_available!) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('get-app-update'),
            onPressed: _opening ? null : _openOfficialDownload,
            icon: _opening
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded),
            label: Text(_opening ? 'Opening…' : 'Get update from GitHub'),
          ),
          if (_handoffOpened)
            const Text(
              'GitHub download opened. After it finishes, open the APK from Downloads; Android will verify the package/signature and ask you to confirm installation. If Android asks, allow installs only from the app you used to download this trusted release.',
              key: Key('app-update-handoff'),
            ),
        ],
      ],
    ],
  );
}
