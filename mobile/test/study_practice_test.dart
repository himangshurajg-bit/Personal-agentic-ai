import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/assistant_state.dart';
import 'package:personal_assistant/study_practice.dart';
import 'package:personal_assistant/phone_screens.dart';

const lesson = '''## Topic explanation
A small lesson.

## Check your understanding
1. What is the main idea?
Hint: Recall the first principle.
2) Apply it to this example.

## Answers and reasoning
1. The main idea is conservation. Because the system is isolated, the total stays constant.
2. Apply conservation to both states, then solve for the unknown.
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AssistantState.device, (_) async => 'nexa_1');
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AssistantState.device, null);
  });

  test('parses matching numbered questions and worked explanations', () {
    final items = StudyPractice.parse(lesson);
    expect(items, hasLength(2));
    expect(items.first.question, contains('What is the main idea?'));
    expect(items.first.question, isNot(contains('Hint:')));
    expect(items.first.hint, 'Recall the first principle.');
    expect(items.first.explanation, contains('system is isolated'));
    expect(items.last.number, 2);
  });

  test(
    'does not start practice if the lesson has no matched answer section',
    () {
      expect(
        StudyPractice.parse('## Check your understanding\n1. One?'),
        isEmpty,
      );
      expect(
        StudyPractice.parse(
          lesson.replaceFirst(
            '2. Apply conservation to both states, then solve for the unknown.',
            '',
          ),
        ),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'hint, attempt, retry, explanation and next question stay local',
    (tester) async {
      final state = AssistantState();
      await state.initialize();
      final id = await state.local.saveStudyLesson(
        topic: 'Conservation',
        explanation: lesson,
        conversationId: 'local-test',
      );
      final items = StudyPractice.parse(lesson);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => StudyPracticeDialog(
                    lessonId: id,
                    topic: 'Conservation',
                    items: items,
                    data: state.local,
                  ),
                ),
                child: const Text('Open practice'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open practice'));
      await tester.pumpAndSettle();
      expect(find.text('Hint: Recall the first principle.'), findsNothing);
      await tester.tap(find.text('Show a hint'));
      await tester.pumpAndSettle();
      expect(find.text('Hint: Recall the first principle.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('study-practice-answer')),
        'My first attempt',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show explanation'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Worked explanation'), findsOneWidget);
      await tester.tap(find.text('Retry this question'));
      await tester.pumpAndSettle();
      final attempts = state.local.snapshot['study_practice_attempts'] as List;
      expect(attempts, hasLength(1));
      expect(attempts.single['self_assessment'], 'still_learning');
      expect(state.local.snapshot['chats'], isEmpty);

      await tester.enterText(
        find.byKey(const ValueKey('study-practice-answer')),
        'Second attempt',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show explanation'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Understood · next'));
      await tester.pumpAndSettle();
      expect(find.text('Practice · 2 of 2'), findsOneWidget);
      expect(state.local.snapshot['study_practice_attempts'], hasLength(2));
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      state.dispose();
    },
  );

  testWidgets('older saved lesson offers user-triggered practice preparation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = AssistantState();
    await state.initialize();
    final id = await state.local.saveStudyLesson(
      topic: 'Older lesson',
      explanation: 'A saved explanation with no questions yet.',
      conversationId: 'local-test',
    );
    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => settings.name == '/chat'
              ? Scaffold(body: Text(settings.arguments as String))
              : StudyWhiteboardScreen(state: state, lessonId: id),
        ),
        home: StudyWhiteboardScreen(state: state, lessonId: id),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('whiteboard-prepare-practice')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('whiteboard-prepare-practice')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Create a short original practice set'),
      findsOneWidget,
    );
    expect(state.messages, isEmpty); // the draft is not sent automatically
    state.dispose();
  });

  test('attempts remain local and are removed with the lesson', () async {
    final state = AssistantState();
    await state.initialize();
    final id = await state.local.saveStudyLesson(
      topic: 'Conservation',
      explanation: lesson,
      conversationId: 'local-test',
    );
    await state.local.saveStudyPracticeAttempt(
      lessonId: id,
      questionNumber: 1,
      answer: 'My attempt',
      selfAssessment: 'still_learning',
    );
    final saved = state.local.snapshot;
    expect(saved['study_practice_attempts'], hasLength(1));
    expect(saved['study_practice_attempts'][0]['answer'], 'My attempt');
    expect(saved['study_practice_attempts'][0]['lesson_id'], id);
    expect(saved['chats'], isEmpty);
    expect(saved['study_practice_attempts'][0], isNot(contains('remote')));

    await state.local.deleteStudyLesson(id);
    expect(state.local.snapshot['study_practice_attempts'], isEmpty);
    state.dispose();
  });
}
