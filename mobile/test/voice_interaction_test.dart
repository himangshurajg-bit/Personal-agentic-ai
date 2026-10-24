import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/main.dart';

void main() {
  testWidgets(
    'voice transcript can be corrected before entering the composer',
    (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showDialog<String>(
                    context: context,
                    builder: (_) => const VoiceTranscriptReviewDialog(
                      transcript: 'Remind me at eight',
                    ),
                  );
                },
                child: const Text('Open review'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open review'));
      await tester.pumpAndSettle();
      expect(find.text('Remind me at eight'), findsOneWidget);
      expect(
        find.text(
          'Correct anything recognition got wrong. Using this transcript only places it in the message box; it does not send or execute anything.',
        ),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('voice-transcript-editor')),
        'Remind me at 8 PM',
      );
      await tester.tap(find.text('Use transcript'));
      await tester.pumpAndSettle();
      expect(result, 'Remind me at 8 PM');
    },
  );

  testWidgets('hands-free transcript requires an explicit send action', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<String>(
                  context: context,
                  builder: (_) => const VoiceTranscriptReviewDialog(
                    transcript: 'What is the speed of light?',
                    sendMessage: true,
                  ),
                );
              },
              child: const Text('Open session review'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open session review'));
    await tester.pumpAndSettle();
    expect(find.text('Send message'), findsOneWidget);
    expect(
      find.textContaining('device actions still need their normal approval'),
      findsOneWidget,
    );
    expect(result, isNull);
    await tester.tap(find.text('Send message'));
    await tester.pumpAndSettle();
    expect(result, 'What is the speed of light?');
  });

  testWidgets('canceling transcript review discards recognition', (
    tester,
  ) async {
    String? result = 'not returned';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<String>(
                  context: context,
                  builder: (_) => const VoiceTranscriptReviewDialog(
                    transcript: 'Open my messages',
                  ),
                );
              },
              child: const Text('Open review'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.text('Open my messages'), findsNothing);
  });
}
