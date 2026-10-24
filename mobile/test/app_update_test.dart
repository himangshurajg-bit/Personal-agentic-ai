import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:personal_assistant/app_update.dart';

const _tag = 'v1.00.00.0000.0-build18';
const _apkUrl =
    'https://github.com/himangshurajg-bit/Personal-agentic-ai/releases/download/$_tag/app-release.apk';
const _pageUrl =
    'https://github.com/himangshurajg-bit/Personal-agentic-ai/releases/tag/$_tag';

Map<String, dynamic> _release({
  String tag = _tag,
  String? pageUrl,
  String? apkUrl,
  bool draft = false,
  bool prerelease = false,
  List<Map<String, dynamic>>? assets,
  String? contentType = 'application/vnd.android.package-archive',
  Object? size = 71 * 1024 * 1024,
}) => {
  'tag_name': tag,
  'name': 'Personal AI $tag',
  'body': 'Voice fixes and improved settings.',
  'draft': draft,
  'prerelease': prerelease,
  'html_url':
      pageUrl ??
      'https://github.com/himangshurajg-bit/Personal-agentic-ai/releases/tag/$tag',
  'assets':
      assets ??
      [
        {
          'name': appReleaseApkName,
          'state': 'uploaded',
          'content_type': contentType,
          'size': size,
          'browser_download_url':
              apkUrl ??
              'https://github.com/himangshurajg-bit/Personal-agentic-ai/releases/download/$tag/$appReleaseApkName',
          'digest': 'sha256:${List.filled(64, 'a').join()}',
        },
      ],
};

class _ReplyClient extends http.BaseClient {
  _ReplyClient(this.response);

  final http.StreamedResponse Function(http.BaseRequest request) response;
  final requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return response(request);
  }
}

http.StreamedResponse _jsonResponse(
  Map<String, dynamic> value, {
  int status = 200,
}) => http.StreamedResponse(
  Stream.value(utf8.encode(jsonEncode(value))),
  status,
  headers: const {'content-type': 'application/json'},
);

void main() {
  group('release metadata validation', () {
    test('accepts a published official APK release', () {
      final release = AppRelease.fromJson(_release());
      expect(release.tag, _tag);
      expect(release.versionName, '1.00.00.0000.0');
      expect(release.buildNumber, 18);
      expect(release.apkDownload.toString(), _apkUrl);
      expect(release.releasePage.toString(), _pageUrl);
      expect(release.notes, 'Voice fixes and improved settings.');
    });

    test('rejects draft and prerelease records', () {
      expect(
        () => AppRelease.fromJson(_release(draft: true)),
        throwsFormatException,
      );
      expect(
        () => AppRelease.fromJson(_release(prerelease: true)),
        throwsFormatException,
      );
    });

    test('rejects unsupported version tags and non-pinned links', () {
      expect(
        () => AppRelease.fromJson(_release(tag: 'latest')),
        throwsFormatException,
      );
      expect(
        () => AppRelease.fromJson(
          _release(pageUrl: 'https://evil.example/release'),
        ),
        throwsFormatException,
      );
      expect(
        () => AppRelease.fromJson(
          _release(apkUrl: 'https://evil.example/app-release.apk'),
        ),
        throwsFormatException,
      );
      expect(
        () => AppRelease.fromJson(
          _release(
            apkUrl:
                'https://github.com.evil.example/releases/download/$_tag/app-release.apk',
          ),
        ),
        throwsFormatException,
      );
    });

    test('rejects missing, duplicate, malformed or oversized APK assets', () {
      expect(
        () => AppRelease.fromJson(_release(assets: const [])),
        throwsFormatException,
      );
      final duplicate = _release()['assets'] as List<Map<String, dynamic>>;
      expect(
        () =>
            AppRelease.fromJson(_release(assets: [...duplicate, ...duplicate])),
        throwsFormatException,
      );
      expect(
        () => AppRelease.fromJson(_release(contentType: 'application/zip')),
        throwsFormatException,
      );
      expect(
        () => AppRelease.fromJson(_release(size: appReleaseMaxBytes + 1)),
        throwsFormatException,
      );
    });

    test(
      'requires app-owned APK to be uploaded and digest shape to be valid',
      () {
        final notUploaded = _release();
        (notUploaded['assets'] as List<Map<String, dynamic>>).single['state'] =
            'starter';
        expect(() => AppRelease.fromJson(notUploaded), throwsFormatException);
        final badDigest = _release();
        (badDigest['assets'] as List<Map<String, dynamic>>).single['digest'] =
            'sha1:broken';
        expect(() => AppRelease.fromJson(badDigest), throwsFormatException);
      },
    );
  });

  group('update version decisions', () {
    const installed = InstalledAppVersion(
      packageName: 'dev.personalagent.personal_assistant',
      versionName: '1.0.0',
      versionCode: 17,
    );

    test('accepts a greater build with the same normalized version', () {
      expect(
        isReleaseNewer(AppRelease.fromJson(_release()), installed),
        isTrue,
      );
    });

    test('rejects the same or older release build', () {
      final same = AppRelease.fromJson(_release(tag: 'v1.0.0.0.0-build17'));
      final old = AppRelease.fromJson(_release(tag: 'v1.0.0.0.0-build16'));
      expect(isReleaseNewer(same, installed), isFalse);
      expect(isReleaseNewer(old, installed), isFalse);
    });

    test('compares numeric version components before build numbers', () {
      final newerVersion = AppRelease.fromJson(
        _release(tag: 'v1.0.1.0.0-build1'),
      );
      final olderVersion = AppRelease.fromJson(
        _release(tag: 'v0.99.99.99.99-build999'),
      );
      expect(isReleaseNewer(newerVersion, installed), isTrue);
      expect(isReleaseNewer(olderVersion, installed), isFalse);
      expect(compareNumericVersions('1.10.0', '1.9.99'), greaterThan(0));
    });

    test('rejects an unexpected installed package identity', () {
      expect(
        () => InstalledAppVersion.fromMap({
          'packageName': 'other.app',
          'versionName': '1.0.0',
          'versionCode': 1,
        }),
        throwsFormatException,
      );
    });
  });

  group('release API and handoff UI', () {
    test('uses the fixed HTTPS endpoint and rejects HTTP errors', () async {
      final client = _ReplyClient(
        (_) => _jsonResponse(_release(), status: 503),
      );
      final service = AppReleaseService(client: client);
      await expectLater(service.fetchLatest(), throwsA(isA<StateError>()));
      expect(client.requests.single.url.toString(), appReleaseApiUrl);
      expect(client.requests.single.followRedirects, isFalse);
      service.close();
    });

    test('bounds release metadata response size while streaming', () async {
      final client = _ReplyClient(
        (_) => http.StreamedResponse(
          Stream<List<int>>.fromIterable([
            List<int>.filled(600 * 1024, 32),
            List<int>.filled(600 * 1024, 32),
          ]),
          200,
        ),
      );
      final service = AppReleaseService(client: client);
      await expectLater(service.fetchLatest(), throwsFormatException);
      service.close();
    });

    testWidgets(
      'checks only on tap and opens official download on a separate tap',
      (tester) async {
        final client = _ReplyClient((_) => _jsonResponse(_release()));
        final service = AppReleaseService(client: client);
        final platform = MethodChannel('app_update_test');
        final platformCalls = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(platform, (call) async {
              platformCalls.add(call);
              if (call.method == 'get_installed_version') {
                return {
                  'packageName': 'dev.personalagent.personal_assistant',
                  'versionName': '1.0.0',
                  'versionCode': 17,
                };
              }
              if (call.method == 'open_official_release_download') return true;
              throw PlatformException(code: 'unexpected');
            });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AppUpdatePanel(service: service, platform: platform),
            ),
          ),
        );
        expect(client.requests, isEmpty);
        expect(find.byKey(const Key('check-app-update')), findsOneWidget);
        expect(find.byKey(const Key('get-app-update')), findsNothing);

        await tester.tap(find.byKey(const Key('check-app-update')));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        expect(client.requests.single.url.toString(), appReleaseApiUrl);
        expect(find.text('Update available'), findsOneWidget);
        expect(find.text('Voice fixes and improved settings.'), findsOneWidget);
        expect(find.byKey(const Key('get-app-update')), findsOneWidget);
        expect(
          platformCalls.where(
            (call) => call.method == 'open_official_release_download',
          ),
          isEmpty,
        );

        await tester.tap(find.byKey(const Key('get-app-update')));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        final openCall = platformCalls.singleWhere(
          (call) => call.method == 'open_official_release_download',
        );
        expect((openCall.arguments as Map)['url'], _apkUrl);
        expect(find.byKey(const Key('app-update-handoff')), findsOneWidget);

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(platform, null);
        service.close();
      },
    );

    testWidgets(
      'shows current state without offering download when not newer',
      (tester) async {
        final older = _release(tag: 'v1.0.0.0.0-build17');
        final service = AppReleaseService(
          client: _ReplyClient((_) => _jsonResponse(older)),
        );
        final platform = MethodChannel('app_update_up_to_date_test');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              platform,
              (call) async => {
                'packageName': 'dev.personalagent.personal_assistant',
                'versionName': '1.0.0',
                'versionCode': 17,
              },
            );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AppUpdatePanel(service: service, platform: platform),
            ),
          ),
        );
        await tester.tap(find.byKey(const Key('check-app-update')));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        expect(find.text('You’re up to date'), findsOneWidget);
        expect(find.byKey(const Key('get-app-update')), findsNothing);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(platform, null);
        service.close();
      },
    );
  });
}
