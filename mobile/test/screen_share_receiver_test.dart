import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_assistant/assistant_state.dart';
import 'package:personal_assistant/screen_share_receiver.dart';

void main() {
  group('boundedJpegDimensions', () {
    Uint8List jpegHeader({int width = 1200, int height = 2400}) =>
        Uint8List.fromList([
          0xff,
          0xd8,
          0xff,
          0xc0,
          0x00,
          0x11,
          0x08,
          (height >> 8) & 0xff,
          height & 0xff,
          (width >> 8) & 0xff,
          width & 0xff,
          0x03,
          0x01,
          0x11,
          0x00,
          0x02,
          0x11,
          0x00,
          0x03,
          0x11,
          0x00,
          0xff,
          0xd9,
        ]);

    test('accepts JPEG dimensions inside the receiver bounds', () {
      final result = boundedJpegDimensions(jpegHeader());
      expect(result?.width, 1200);
      expect(result?.height, 2400);
    });

    test('rejects oversized and malformed JPEGs before image decode', () {
      expect(boundedJpegDimensions(jpegHeader(width: 5000)), isNull);
      expect(
        boundedJpegDimensions(jpegHeader(width: 4096, height: 2049)),
        isNull,
      );
      expect(
        boundedJpegDimensions(Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9])),
        isNull,
      );
    });

    test('rejects an oversized stream before buffering its body', () async {
      final response = http.StreamedResponse(
        Stream<List<int>>.value(List<int>.filled(1500001, 0)),
        200,
      );
      await expectLater(
        readBoundedScreenFrame(response),
        throwsA(isA<ServiceException>()),
      );
    });

    test(
      'rejects an oversized declared content length without reading',
      () async {
        final response = http.StreamedResponse(
          const Stream<List<int>>.empty(),
          200,
          contentLength: 1500001,
        );
        await expectLater(
          readBoundedScreenFrame(response),
          throwsA(isA<ServiceException>()),
        );
      },
    );
  });

  testWidgets('explains pairing approval and missing service setup', (
    tester,
  ) async {
    final state = AssistantState(
      clientFactory: () => MockClient((_) async => http.Response('[]', 200)),
    );
    await tester.pumpWidget(
      MaterialApp(home: ScreenShareReceiverScreen(state: state)),
    );
    await tester.pump();

    expect(find.text('Pair first. Approve each share.'), findsOneWidget);
    expect(
      find.textContaining('Set the private service endpoint'),
      findsOneWidget,
    );
    expect(find.text('Create pairing code'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets('requires a separate approval for the exact pending session', (
    tester,
  ) async {
    const pairingId = '0123456789abcdef0123456789abcdef';
    const sessionId = 'abcdef0123456789abcdef0123456789';
    final requests = <http.Request>[];
    final state =
        AssistantState(
            clientFactory: () => MockClient((request) async {
              requests.add(request);
              if (request.url.path == '/screen-share/pairings') {
                return http.Response(
                  jsonEncode([
                    {
                      'pairing_id': pairingId,
                      'state': 'paired',
                      'sender_label': 'MYRA Android',
                    },
                  ]),
                  200,
                  headers: {'content-type': 'application/json'},
                );
              }
              if (request.url.path == '/screen-share/sessions' &&
                  request.method == 'GET') {
                return http.Response(
                  jsonEncode([
                    {
                      'session_id': sessionId,
                      'pairing_id': pairingId,
                      'state': 'awaiting_receiver_approval',
                    },
                  ]),
                  200,
                  headers: {'content-type': 'application/json'},
                );
              }
              if (request.url.path ==
                  '/screen-share/sessions/$sessionId/approve') {
                return http.Response(
                  jsonEncode({'session_id': sessionId, 'state': 'approved'}),
                  200,
                  headers: {'content-type': 'application/json'},
                );
              }
              return http.Response('not found', 404);
            }),
          )
          ..privateServiceEndpoint = 'https://receiver.example.test'
          ..privateServiceToken = 'test-token';

    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: ScreenShareReceiverScreen(state: state)),
    );
    await tester.pumpAndSettle();
    expect(
      requests.map((request) => request.url.path),
      contains('/screen-share/sessions'),
    );
    expect(find.text('Review and approve'), findsOneWidget);
    expect(
      requests.where((request) => request.url.path.endsWith('/approve')),
      isEmpty,
    );

    await tester.tap(find.text('Review and approve'));
    await tester.pumpAndSettle();
    expect(find.text('Allow this screen share?'), findsOneWidget);
    expect(
      find.textContaining('Android’s own screen-capture consent'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(
      requests.where((request) => request.url.path.endsWith('/approve')),
      isEmpty,
    );

    await tester.tap(find.text('Review and approve'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve this session'));
    await tester.pumpAndSettle();
    expect(
      requests.where(
        (request) =>
            request.url.path == '/screen-share/sessions/$sessionId/approve',
      ),
      hasLength(1),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets('creates and shows only the short-lived one-time code', (
    tester,
  ) async {
    const pairingId = '0123456789abcdef0123456789abcdef';
    const pairingCode = '0123456789abcdef0123456789abcdef';
    final state =
        AssistantState(
            clientFactory: () => MockClient((request) async {
              if (request.url.path == '/screen-share/pairings' &&
                  request.method == 'POST') {
                return http.Response(
                  jsonEncode({
                    'pairing_id': pairingId,
                    'pairing_code': pairingCode,
                    'expires_in_seconds': 300,
                    'state': 'waiting_for_sender',
                  }),
                  200,
                  headers: {'content-type': 'application/json'},
                );
              }
              if (request.url.path == '/screen-share/pairings') {
                return http.Response(
                  jsonEncode([
                    {
                      'pairing_id': pairingId,
                      'state': 'waiting_for_sender',
                      'sender_label': null,
                    },
                  ]),
                  200,
                  headers: {'content-type': 'application/json'},
                );
              }
              if (request.url.path == '/screen-share/sessions') {
                return http.Response(
                  '[]',
                  200,
                  headers: {'content-type': 'application/json'},
                );
              }
              return http.Response('not found', 404);
            }),
          )
          ..privateServiceEndpoint = 'https://receiver.example.test'
          ..privateServiceToken = 'test-token';

    await tester.pumpWidget(
      MaterialApp(home: ScreenShareReceiverScreen(state: state)),
    );
    await tester.pump();
    await tester.tap(find.text('Create pairing code'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('screen-share-pairing-code')), findsOneWidget);
    expect(find.text(pairingCode), findsOneWidget);
    expect(find.textContaining('One-time code · expires'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets('can stop an active share and revoke the paired sender', (
    tester,
  ) async {
    const pairingId = '0123456789abcdef0123456789abcdef';
    const sessionId = 'abcdef0123456789abcdef0123456789';
    var paired = true;
    var sessionActive = true;
    final requests = <http.Request>[];
    final state =
        AssistantState(
            clientFactory: () => MockClient((request) async {
              requests.add(request);
              if (request.url.path == '/screen-share/pairings' &&
                  request.method == 'GET') {
                return http.Response(
                  jsonEncode(
                    paired
                        ? [
                            {
                              'pairing_id': pairingId,
                              'state': 'paired',
                              'sender_label': 'Test sender',
                            },
                          ]
                        : [],
                  ),
                  200,
                  headers: {'content-type': 'application/json'},
                );
              }
              if (request.url.path == '/screen-share/sessions' &&
                  request.method == 'GET') {
                return http.Response(
                  jsonEncode(
                    sessionActive
                        ? [
                            {
                              'session_id': sessionId,
                              'pairing_id': pairingId,
                              'state': 'active',
                            },
                          ]
                        : [],
                  ),
                  200,
                  headers: {'content-type': 'application/json'},
                );
              }
              if (request.url.path ==
                      '/screen-share/sessions/$sessionId/frame' &&
                  request.method == 'GET') {
                return http.Response('', 204);
              }
              if (request.url.path ==
                      '/screen-share/sessions/$sessionId/stop' &&
                  request.method == 'POST') {
                sessionActive = false;
                return http.Response(
                  jsonEncode({'session_id': sessionId, 'state': 'stopped'}),
                  200,
                  headers: {'content-type': 'application/json'},
                );
              }
              if (request.url.path ==
                      '/screen-share/pairings/$pairingId/revoke' &&
                  request.method == 'POST') {
                paired = false;
                return http.Response(
                  jsonEncode({'pairing_id': pairingId, 'state': 'revoked'}),
                  200,
                  headers: {'content-type': 'application/json'},
                );
              }
              return http.Response('not found', 404);
            }),
          )
          ..privateServiceEndpoint = 'https://receiver.example.test'
          ..privateServiceToken = 'test-token';

    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: ScreenShareReceiverScreen(state: state)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Screen share is active'), findsOneWidget);

    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    expect(find.text('Stop screen sharing?'), findsOneWidget);
    await tester.tap(find.text('Stop this session'));
    await tester.pumpAndSettle();
    expect(
      requests.where(
        (request) =>
            request.url.path == '/screen-share/sessions/$sessionId/stop',
      ),
      hasLength(1),
    );
    expect(
      find.text('No pending or active screen-share sessions.'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Revoke paired device'));
    await tester.pumpAndSettle();
    expect(find.text('Remove paired device?'), findsOneWidget);
    await tester.tap(find.text('Revoke device'));
    await tester.pumpAndSettle();
    expect(
      requests.where(
        (request) =>
            request.url.path == '/screen-share/pairings/$pairingId/revoke',
      ),
      hasLength(1),
    );
    expect(find.text('No paired sender is available yet.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });
}
