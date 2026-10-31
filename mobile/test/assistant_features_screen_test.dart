import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/assistant_features_screen.dart';
import 'package:personal_assistant/assistant_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('personal_assistant/device');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'list_user_downloads') return <Object?>[];
          if (call.method == 'enqueue_user_download') {
            return <String, Object?>{'id': 21, 'file_name': 'report.pdf'};
          }
          return <String, Object?>{
            'chooser_opened': true,
            'shared_online': false,
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('download is not enqueued until exact URL review is approved', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FeaturesScreen(
          state: AssistantState(),
          onReminder: (context, value) async {},
          initialTab: 11,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      'https://example.com/report.pdf',
    );
    await tester.pump();
    expect(
      calls.where((call) => call.method == 'enqueue_user_download'),
      isEmpty,
    );
    await tester.tap(find.text('Review and download'));
    await tester.pumpAndSettle();
    expect(find.text('Review download'), findsOneWidget);
    expect(
      find.textContaining('https://example.com/report.pdf'),
      findsNWidgets(2),
    );
    expect(
      calls.where((call) => call.method == 'enqueue_user_download'),
      isEmpty,
    );
    await tester.tap(find.text('Start download'));
    await tester.pumpAndSettle();
    final enqueue = calls
        .where((call) => call.method == 'enqueue_user_download')
        .single;
    expect(enqueue.arguments, {
      'url': 'https://example.com/report.pdf',
      'file_name': 'report.pdf',
    });
  });

  testWidgets('local PDF and video viewing stays separate from Gemini upload', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FeaturesScreen(
          state: AssistantState(),
          onReminder: (context, value) async {},
        ),
      ),
    );
    await tester.tap(find.text('Open PDF locally'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open video locally'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Local audio queue'));
    await tester.pumpAndSettle();

    expect(calls.map((call) => call.method), [
      'open_local_media',
      'open_local_media',
      'open_local_media',
    ]);
    expect(calls.map((call) => call.arguments), [
      {'kind': 'pdf'},
      {'kind': 'video'},
      {'kind': 'audio'},
    ]);
    await tester.scrollUntilVisible(
      find.textContaining('nothing is sent to Gemini'),
      250,
      scrollable: find.descendant(
        of: find.byType(ListView).first,
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.textContaining('nothing is sent to Gemini'), findsOneWidget);
  });
  testWidgets('camera photo is selected locally without sending it', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return <String, Object?>{
            'name': 'Camera photo',
            'mime': 'image/jpeg',
            'content_base64': '/9gA/9k=',
          };
        });
    await tester.pumpWidget(
      MaterialApp(
        home: FeaturesScreen(
          state: AssistantState(),
          onReminder: (context, value) async {},
        ),
      ),
    );
    await tester.tap(find.text('Take a photo'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Camera photo'),
      250,
      scrollable: find.descendant(
        of: find.byType(ListView).first,
        matching: find.byType(Scrollable),
      ),
    );

    expect(calls.single.method, 'capture_photo');
    expect(find.text('Camera photo'), findsOneWidget);
    expect(calls.map((call) => call.method), ['capture_photo']);
  });

  testWidgets('image OCR stays on device and is not sent to Gemini', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'capture_photo') {
            return <String, Object?>{
              'name': 'Camera photo',
              'mime': 'image/jpeg',
              'content_base64': '/9gA/9k=',
            };
          }
          if (call.method == 'extract_image_text_locally') {
            return 'Recognized local text';
          }
          return null;
        });
    await tester.pumpWidget(
      MaterialApp(
        home: FeaturesScreen(
          state: AssistantState(),
          onReminder: (context, value) async {},
        ),
      ),
    );
    await tester.tap(find.text('Take a photo'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Camera photo'),
      250,
      scrollable: find.descendant(
        of: find.byType(ListView).first,
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Camera photo'), findsOneWidget);
    expect(calls.single.method, 'capture_photo');
    await tester.scrollUntilVisible(
      find.text('Extract text on device'),
      250,
      scrollable: find.descendant(
        of: find.byType(ListView).first,
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.text('Extract text on device'));
    await tester.pumpAndSettle();

    expect(calls.map((call) => call.method), [
      'capture_photo',
      'extract_image_text_locally',
    ]);
    final ocrArgs = calls.last.arguments as Map<Object?, Object?>;
    expect(ocrArgs['mime'], 'image/jpeg');
    expect(ocrArgs['image_bytes'], isA<Uint8List>());
    expect(find.text('Recognized local text'), findsOneWidget);
    expect(find.textContaining('not added to chat'), findsOneWidget);
  });

  testWidgets('PDF OCR is a local explicit action and keeps review separate', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'pick_file') {
            return <String, Object?>{
              'name': 'selected.pdf',
              'mime': 'application/pdf',
              'content_base64': base64Encode(<int>[37, 80, 68, 70]),
            };
          }
          if (call.method == 'extract_pdf_text_locally') {
            return <String, Object?>{
              'text': 'Page 1\nRecognized PDF text',
              'pages_processed': 2,
              'page_count': 4,
              'truncated': true,
            };
          }
          return null;
        });
    await tester.pumpWidget(
      MaterialApp(
        home: FeaturesScreen(
          state: AssistantState(),
          onReminder: (context, value) async {},
        ),
      ),
    );
    await tester.tap(find.text('Choose PDF, DOCX or photo'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Extract PDF text on device'),
      250,
      scrollable: find.descendant(
        of: find.byType(ListView).first,
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.text('Extract PDF text on device'));
    await tester.pumpAndSettle();

    expect(calls.map((call) => call.method), [
      'pick_file',
      'extract_pdf_text_locally',
    ]);
    final ocrArgs = calls.last.arguments as Map<Object?, Object?>;
    expect(ocrArgs['mime'], 'application/pdf');
    expect(ocrArgs['pdf_bytes'], isA<Uint8List>());
    expect(find.text('Page 1\nRecognized PDF text'), findsOneWidget);
    expect(
      find.text('Read 2 of 4 pages locally · partial result.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('PDF is not uploaded by this action'),
      findsOneWidget,
    );
  });

  testWidgets('Text tools transform locally without calling device services', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FeaturesScreen(
          state: AssistantState(),
          onReminder: (context, value) async {},
        ),
      ),
    );
    await tester.tap(find.text('Text tools'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'hello');
    await tester.tap(find.text('Transform locally'));
    await tester.pumpAndSettle();

    expect(find.text('aGVsbG8='), findsOneWidget);
    expect(calls, isEmpty);
    expect(find.textContaining('not saved or sent online'), findsOneWidget);
  });
}
