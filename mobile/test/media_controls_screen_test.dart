import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/media_controls_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('personal_assistant/device');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets(
    'media search requires exact-query review and never starts playback',
    (tester) async {
      MethodCall? call;
      messenger.setMockMethodCallHandler(channel, (received) async {
        call = received;
        return {
          'opened': true,
          'playback_started': false,
          'service': 'youtube',
          'query': 'lofi study',
        };
      });
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: MediaControlsScreen())),
      );
      await tester.enterText(
        find.byKey(const Key('media-query')),
        'lofi study',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('media-review-search')),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('media-review-search')));
      await tester.pumpAndSettle();
      final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
      expect(
        (dialog.content as Text).data,
        contains('Search for “lofi study”?'),
      );
      expect(call, isNull);
      await tester.tap(find.text('Open search'));
      await tester.pumpAndSettle();
      expect(call?.method, 'open_media_search');
      expect(call?.arguments, {'service': 'youtube', 'query': 'lofi study'});
      expect(
        find.text(
          'Android opened the search handoff. Playback was not started.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('canceling a media review makes no platform request', (
    tester,
  ) async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      return null;
    });
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: MediaControlsScreen())),
    );
    await tester.enterText(find.byKey(const Key('media-query')), 'song');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('media-review-search')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('media-review-search')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(calls, 0);
  });

  testWidgets('volume is read only on tap and an exact change is reviewed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'read_volume_state') {
        return {
          'stream': 'music',
          'current': 5,
          'min': 0,
          'max': 10,
          'percent': 50,
        };
      }
      if (call.method == 'set_reviewed_volume') {
        return {
          'stream': 'music',
          'requested_percent': 50,
          'actual_percent': 50,
          'current': 5,
          'min': 0,
          'max': 10,
          'applied': true,
        };
      }
      return null;
    });
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: MediaControlsScreen())),
    );
    expect(calls, isEmpty);

    await tester.tap(find.byKey(const Key('volume-read')));
    await tester.pumpAndSettle();
    expect(calls.single.method, 'read_volume_state');
    expect(find.text('Current: 5 of 10 · 50%'), findsOneWidget);

    await tester.tap(find.byKey(const Key('volume-review-apply')));
    await tester.pumpAndSettle();
    expect(find.text('Set Music volume to 50%?'), findsOneWidget);
    expect(calls.length, 1);
    await tester.tap(find.text('Apply volume'));
    await tester.pumpAndSettle();
    expect(calls.last.method, 'set_reviewed_volume');
    expect(calls.last.arguments, {'stream': 'music', 'percent': 50});
    expect(
      find.text('Android reports music volume set to 50%.'),
      findsOneWidget,
    );
  });
}
