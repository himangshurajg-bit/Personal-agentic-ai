import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/clipboard_preview_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reads only after tap and clears the local preview', (tester) async {
    var reads = 0;
    const clipboardChannel = MethodChannel('personal_assistant/clipboard_preview');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(clipboardChannel, (call) async {
      if (call.method == 'read_plain_text') {
        reads++;
        return 'private sample';
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(clipboardChannel, null));

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ClipboardPreviewScreen())),
    );
    expect(reads, 0);
    expect(find.text('Clipboard is not read automatically.'), findsOneWidget);

    await tester.tap(find.text('Read clipboard'));
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(find.text('private sample'), findsOneWidget);
    expect(find.textContaining('not been sent or saved'), findsOneWidget);

    await tester.tap(find.text('Clear preview'));
    await tester.pumpAndSettle();
    expect(find.text('private sample'), findsNothing);
    expect(find.text('Cleared the local clipboard preview.'), findsOneWidget);
  });

  testWidgets('shows a plain-text unavailable result without content', (tester) async {
    const clipboardChannel = MethodChannel('personal_assistant/clipboard_preview');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(clipboardChannel, (call) async {
      if (call.method == 'read_plain_text') return null;
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(clipboardChannel, null));

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ClipboardPreviewScreen())),
    );
    await tester.tap(find.text('Read clipboard'));
    await tester.pumpAndSettle();
    expect(find.textContaining('no plain text'), findsOneWidget);
  });
}
