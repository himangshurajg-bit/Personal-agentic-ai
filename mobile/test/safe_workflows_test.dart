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
          if (call.method == 'open_whatsapp_draft') {
            return <String, Object?>{'result': 'handoff_opened', 'sent': false};
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets(
    'WhatsApp handoff stays inert until exact recipient and draft are approved',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: OutboundDraftsScreen()));

      expect(
        find.textContaining('Nothing is sent or published by this app.'),
        findsOneWidget,
      );
      expect(find.text('Review WhatsApp draft'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(calls, isEmpty);

      await tester.enterText(
        find.byKey(const ValueKey('outbound-draft-number')),
        '+14155550123',
      );
      await tester.enterText(
        find.byKey(const ValueKey('outbound-draft-text')),
        'Please send me the class notes when you can.',
      );
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      expect(calls, isEmpty);

      final reviewButton = find.text('Review WhatsApp draft');
      await tester.ensureVisible(reviewButton);
      await tester.pumpAndSettle();
      await tester.tap(reviewButton);
      await tester.pumpAndSettle();
      expect(calls, hasLength(1));
      expect(calls.single.method, 'open_whatsapp_draft');
      expect(calls.single.arguments, {
        'number': '+14155550123',
        'message': 'Please send me the class notes when you can.',
      });
    },
  );

  testWidgets('WhatsApp recipient must be a full international number', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: OutboundDraftsScreen()));
    await tester.enterText(
      find.byKey(const ValueKey('outbound-draft-text')),
      'A reviewed reply.',
    );
    await tester.enterText(
      find.byKey(const ValueKey('outbound-draft-number')),
      '4155550123',
    );
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(calls, isEmpty);
  });

  testWidgets('social caption uses the same explicit text-only chooser', (
    tester,
  ) async {
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
    final captionShareButton = find.text('Choose app to review caption');
    await tester.ensureVisible(captionShareButton);
    await tester.pumpAndSettle();
    await tester.tap(captionShareButton);
    await tester.pumpAndSettle();
    expect(calls.single.arguments, {
      'title': 'Review social caption',
      'text': 'A small study step today.',
    });
  });

  testWidgets(
    'workflow steps can be reordered and optional steps removed/restored',
    (tester) async {
      final state = AssistantState();
      await tester.pumpWidget(
        MaterialApp(home: MultiAgentWorkflowScreen(state: state)),
      );

      expect(find.byTooltip('Remove Planner'), findsOneWidget);
      expect(find.byTooltip('Remove Specialist'), findsOneWidget);
      expect(find.byTooltip('Remove Reviewer'), findsNothing);
      expect(find.byTooltip('Remove Synthesizer'), findsNothing);

      final specialistUp = find
          .descendant(
            of: find.byKey(const ValueKey('workflow-step-specialist')),
            matching: find.byType(IconButton),
          )
          .first;
      final specialistUpButton = tester.widget<IconButton>(specialistUp);
      expect(specialistUpButton.onPressed, isNotNull);
      specialistUpButton.onPressed!();
      await tester.pumpAndSettle();
      final orderedIds = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((tile) => tile.key)
          .whereType<ValueKey<String>>()
          .map((key) => key.value)
          .where((key) => key.startsWith('workflow-step-'))
          .toList();
      expect(orderedIds, [
        'workflow-step-specialist',
        'workflow-step-planner',
        'workflow-step-reviewer',
        'workflow-step-synthesizer',
      ]);

      final removePlanner = find
          .descendant(
            of: find.byKey(const ValueKey('workflow-step-planner')),
            matching: find.byType(IconButton),
          )
          .last;
      await tester.ensureVisible(removePlanner);
      final removePlannerButton = tester.widget<IconButton>(removePlanner);
      expect(removePlannerButton.onPressed, isNotNull);
      removePlannerButton.onPressed!();
      await tester.pumpAndSettle();
      expect(find.text('Add Planner'), findsOneWidget);
      expect(find.byTooltip('Remove Planner'), findsNothing);
      final addPlanner = tester.widget<ActionChip>(
        find.widgetWithText(ActionChip, 'Add Planner'),
      );
      expect(addPlanner.onPressed, isNotNull);
      addPlanner.onPressed!();
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove Planner'), findsOneWidget);
    },
  );

  testWidgets(
    'skills page exposes local actions and a bounded multi-agent workflow',
    (tester) async {
      final state = AssistantState();
      await tester.pumpWidget(
        MaterialApp(home: SafeSkillsScreen(state: state)),
      );
      expect(find.text('Open a study app'), findsOneWidget);
      expect(find.text('Prepare a study reminder'), findsOneWidget);
      expect(find.text('Turn flashlight off'), findsOneWidget);
      expect(
        find.textContaining('Android asks for approval first'),
        findsOneWidget,
      );
      expect(find.text('Try a multi-agent workflow'), findsOneWidget);
      expect(calls, isEmpty);

      final torchOff = find.byKey(const ValueKey('torch-off-action'));
      await tester.ensureVisible(torchOff);
      await tester.pumpAndSettle();
      await tester.tap(torchOff);
      await tester.pumpAndSettle();
      expect(calls, hasLength(1));
      expect(calls.single.method, 'turn_torch_off');
      calls.clear();

      final workflowEntry = find.byKey(
        const ValueKey('multi-agent-workflow-entry'),
      );
      await tester.ensureVisible(workflowEntry);
      await tester.pumpAndSettle();
      await tester.tap(workflowEntry);
      await tester.pumpAndSettle();
      expect(find.text('A small team, one model'), findsOneWidget);
      expect(
        find.textContaining(
          'Select and configure an OpenAI-compatible online model',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('review-multi-agent-run')),
            )
            .onPressed,
        isNull,
      );
      expect(calls, isEmpty);
    },
  );
}
