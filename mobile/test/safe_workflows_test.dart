import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/assistant_state.dart';
import 'package:personal_assistant/safe_workflows.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('personal_assistant/device');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'share_text') {
            return <String, Object?>{'result': 'chooser_opened', 'sent': false};
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('draft preview stays inert until explicit share-sheet tap', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OutboundDraftsScreen()));

    expect(find.textContaining('Nothing is sent or published by this app.'), findsOneWidget);
    expect(find.text('Choose app to review reply'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    expect(calls, isEmpty);

    await tester.enterText(
      find.byKey(const ValueKey('outbound-draft-text')),
      'Please send me the class notes when you can.',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
    expect(calls, isEmpty);

    await tester.tap(find.text('Choose app to review reply'));
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));
    expect(calls.single.method, 'share_text');
    expect(calls.single.arguments, {
      'title': 'Review WhatsApp reply',
      'text': 'Please send me the class notes when you can.',
    });
  });

  testWidgets('social caption uses the same explicit text-only chooser', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OutboundDraftsScreen()));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Social post caption').last);
    await tester.pumpAndSettle();
    expect(find.text('Choose app to review caption'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('outbound-draft-text')),
      'A small study step today.',
    );
    await tester.pump();
    await tester.tap(find.text('Choose app to review caption'));
    await tester.pumpAndSettle();
    expect(calls.single.arguments, {
      'title': 'Review social caption',
      'text': 'A small study step today.',
    });
  });

  testWidgets('skills page exposes only local reviewed actions and labels agents unavailable', (tester) async {
    final state = AssistantState();
    await tester.pumpWidget(MaterialApp(home: SafeSkillsScreen(state: state)));
    expect(find.text('Open a study app'), findsOneWidget);
    expect(find.text('Prepare a study reminder'), findsOneWidget);
    expect(find.text('Sub-agent execution isn’t available yet'), findsOneWidget);
    expect(find.textContaining('does not invoke them or delegate chat work'), findsOneWidget);
    expect(calls, isEmpty);
  });
}
