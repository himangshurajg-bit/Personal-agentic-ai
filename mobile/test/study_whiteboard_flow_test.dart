import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_assistant/assistant_state.dart';
import 'package:personal_assistant/main.dart';
import 'package:personal_assistant/phone_screens.dart';

const _lesson = '''## Topic explanation
Newton's second law relates net force, mass, and acceleration.

## Worked example
A 2 kg object under 6 N net force accelerates at 3 m/s².

## Basic foundations
1. What is the SI unit of force?
2. What is the acceleration of a 2 kg object under 6 N?

## JEE Main practice
3. A 4 kg body has net force 12 N. Find acceleration.
4. Two opposite forces, 10 N and 4 N, act on 2 kg. Find acceleration.
5. A 3 kg body accelerates at 2 m/s². Find its net force.

## JEE Advanced practice
6. A 2 kg block is pulled by 10 N with 2 N friction. Find acceleration.
7. Two blocks of 2 kg and 3 kg move together under 10 N. Find acceleration and contact force.
8. A 5 kg body has force F(t)=10+5t N. Find acceleration at t=2 s.

## Answers and reasoning
1. N = kg·m/s².
2. a=F/m=6/2=3 m/s².
3. a=12/4=3 m/s².
4. Fnet=10-4=6 N, so a=3 m/s².
5. F=ma=3×2=6 N.
6. Fnet=10-2=8 N, so a=8/2=4 m/s².
7. a=10/(2+3)=2 m/s²; contact force on 2 kg block is 2×2=4 N.
8. F(2)=20 N, so a=20/5=4 m/s².

These are original JEE-style questions, not verified PYQs.''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      (_) async => 1,
    );
    messenger.setMockMethodCallHandler(
      AssistantState.device,
      (_) async => true,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      (_) async => null,
    );
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      null,
    );
    messenger.setMockMethodCallHandler(AssistantState.device, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      null,
    );
  });

  Future<AssistantState> buildOnlineState({required bool studyMode}) async {
    final state = AssistantState(
      clientFactory: () => MockClient.streaming((request, body) async {
        final bodyJson = jsonDecode(utf8.decode(await body.toBytes())) as Map;
        final prompt = jsonDecode(bodyJson['text'] as String) as Map;
        requestHeadersAndPrompt.add(prompt);
        final response = jsonEncode({'type': 'delta', 'text': _lesson});
        return http.StreamedResponse(
          Stream.value(utf8.encode('$response\n{"type":"done"}\n')),
          200,
        );
      }),
    );
    await state.initialize();
    state.engine = 'private_service';
    state.chatMode = 'online';
    state.privateServiceToken = 'test-token';
    state.privateServiceEndpoint = 'https://provider.example';
    state.model = 'test-model';
    state.studyModeEnabled = studyMode;
    await state.selectConversation('study-flow-test', load: false);
    return state;
  }

  Future<_ImmediateStudyState> buildUiState({required bool studyMode}) async {
    final state = _ImmediateStudyState(studyMode: studyMode);
    await state.initialize();
    state.studyModeEnabled = studyMode;
    await state.selectConversation('study-ui-test', load: false);
    if (studyMode) {
      state.lessonId = await state.local.saveStudyLesson(
        topic: 'Newton’s second law',
        explanation: _lesson,
        conversationId: 'study-ui-test',
      );
    }
    return state;
  }

  test(
    'Study Mode toggle persists independently of AI response mode',
    () async {
      final state = AssistantState();
      await state.initialize();
      await state.saveStudyModeEnabled(true);
      expect(state.studyModeEnabled, isTrue);
      expect(await state.storage.read(key: 'study_mode_enabled'), 'yes');
      expect(state.aiMode, 'professional');

      final reopened = AssistantState();
      await reopened.initialize();
      expect(reopened.studyModeEnabled, isTrue);
      expect(reopened.aiMode, 'professional');
      state.dispose();
      reopened.dispose();
    },
  );

  test(
    'direct study request stores completed answer and progressive prompt',
    () async {
      requestHeadersAndPrompt.clear();
      final state = await buildOnlineState(studyMode: true);
      await state.send('Newton’s second law');
      expect(state.busy, isFalse);
      expect(state.error, isEmpty);
      expect(state.messages.last['state'], 'complete');
      expect(state.local.studyLessons, hasLength(1));
      final instruction =
          requestHeadersAndPrompt.single['instruction'] as String;
      expect(instruction, contains('Make eight topic-specific questions'));
      expect(instruction, contains('## JEE Main practice'));
      expect(instruction, contains('## JEE Advanced practice'));
      expect(instruction, contains('Never invent an exam year'));
      expect(
        requestHeadersAndPrompt.single['user_message'],
        'Newton’s second law',
      );
      state.dispose();
    },
  );

  test(
    'ordinary chat saves no study lesson and does not add the study prompt',
    () async {
      requestHeadersAndPrompt.clear();
      final state = await buildOnlineState(studyMode: false);
      await state.send('Newton’s second law');
      expect(state.busy, isFalse);
      expect(state.error, isEmpty);
      expect(state.messages.last['role'], 'assistant');
      expect(state.messages.last['state'], 'complete');
      expect(state.local.studyLessons, isEmpty);
      expect(
        requestHeadersAndPrompt.single['instruction'],
        isNot(contains('STUDY WHITEBOARD MODE')),
      );
      state.dispose();
    },
  );

  testWidgets('Study Mode saves generated topic and navigates to Whiteboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = await buildUiState(studyMode: true);

    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/whiteboard': (context) => StudyWhiteboardScreen(
            state: state,
            lessonId: ModalRoute.of(context)?.settings.arguments as String?,
          ),
        },
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: ChatScreen(state: state),
        ),
      ),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, 'Newton’s second law');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(state.error, isEmpty, reason: state.error);
    expect(state.busy, isFalse);
    expect(state.messages.last['role'], 'assistant');
    expect(state.local.studyLessons, hasLength(1));

    expect(find.text('Study Whiteboard'), findsOneWidget);
    expect(find.text('Newton’s second law'), findsWidgets);
    expect(find.textContaining('Newton\'s second law relates'), findsOneWidget);
    expect(state.local.studyLessons, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    state.dispose();
  });

  testWidgets(
    'Study Mode off keeps the actual reply in chat and saves no lesson',
    (tester) async {
      tester.view.physicalSize = const Size(390, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = await buildUiState(studyMode: false);

      await tester.pumpWidget(
        MaterialApp(
          routes: {
            '/whiteboard': (context) => StudyWhiteboardScreen(
              state: state,
              lessonId: ModalRoute.of(context)?.settings.arguments as String?,
            ),
          },
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: ChatScreen(state: state),
          ),
        ),
      );
      await tester.pump();
      await tester.enterText(
        find.byType(TextField).last,
        'Newton’s second law',
      );
      await tester.tap(find.byTooltip('Send message'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();

      expect(state.error, isEmpty, reason: state.error);
      expect(state.busy, isFalse);
      expect(state.messages.last['role'], 'assistant');
      expect(state.local.studyLessons, isEmpty);

      expect(find.byType(StudyWhiteboardScreen), findsNothing);
      expect(
        find.textContaining('Newton\'s second law relates'),
        findsOneWidget,
      );
      expect(state.local.studyLessons, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      state.dispose();
    },
  );
}

class _ImmediateStudyState extends AssistantState {
  _ImmediateStudyState({required bool studyMode}) {
    studyModeEnabled = studyMode;
  }

  String? lessonId;

  @override
  Future<void> send(
    String text, {
    bool shareMemories = false,
    bool shareHistory = false,
    bool retryLastMessage = false,
    bool spokenConversation = false,
  }) async {
    lastStudyLessonId = studyModeEnabled ? lessonId : null;
    messages.add({'role': 'user', 'text': text, 'state': 'complete'});
    messages.add({'role': 'assistant', 'text': _lesson, 'state': 'complete'});
    notifyListeners();
  }
}

final List<Map> requestHeadersAndPrompt = [];
