import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_assistant/assistant_state.dart';
import 'package:personal_assistant/local_web_projects.dart';
import 'package:personal_assistant/local_web_projects_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Finder briefField() => find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        widget.decoration?.labelText ==
            'What should the website do or look like?',
  );

  testWidgets('canceling the online-generation review sends nothing', (
    tester,
  ) async {
    var sent = 0;
    final state = AssistantState(
      clientFactory: () => MockClient((request) async {
        sent++;
        return http.Response('{}', 200);
      }),
    )..geminiApiKey = 'test-key';
    await state.local.load();
    await LocalWebProjects(state.local).create('Local draft');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LocalWebProjectsScreen(state: state)),
      ),
    );
    await tester.tap(find.text('Local draft'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      briefField(),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(briefField(), 'Make a simple study homepage');
    await tester.scrollUntilVisible(
      find.text('Generate with Gemini'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Generate with Gemini'), findsOneWidget);
    await tester.tap(find.text('Generate with Gemini'));
    await tester.pumpAndSettle();

    expect(find.text('Send project to Gemini?'), findsOneWidget);
    expect(sent, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(sent, 0);
    state.dispose();
  });

  testWidgets('generated code requires review and a separate local save', (
    tester,
  ) async {
    final requests = <http.Request>[];
    const generatedHtml = '<!doctype html><title>Study hub</title>';
    const generatedCss = 'body { color: teal; }';
    const generatedJs = '';
    final state = AssistantState(
      clientFactory: () => MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {
                      'text': jsonEncode({
                        'html': generatedHtml,
                        'css': generatedCss,
                        'js': generatedJs,
                      }),
                    },
                  ],
                },
              },
            ],
          }),
          200,
        );
      }),
    )..geminiApiKey = 'test-key';
    await state.local.load();
    final repository = LocalWebProjects(state.local);
    await repository.create('Local draft');
    final originalHtml = repository.all().single['html'];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LocalWebProjectsScreen(state: state)),
      ),
    );
    await tester.tap(find.text('Local draft'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      briefField(),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(briefField(), 'Make a study landing page');
    await tester.scrollUntilVisible(
      find.text('Generate with Gemini'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Generate with Gemini'), findsOneWidget);
    await tester.tap(find.text('Generate with Gemini'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send and generate'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(requests, hasLength(1));
    expect(requests.single.headers['x-goog-api-key'], 'test-key');
    expect(find.text('Review generated website'), findsOneWidget);
    expect(find.text(generatedHtml), findsOneWidget);
    expect(repository.all().single['html'], originalHtml);

    await tester.tap(find.text('Use in editor'));
    await tester.pumpAndSettle();
    expect(find.text('Review generated website'), findsNothing);
    expect(
      find.text('Draft loaded for review. Save it yourself when ready.'),
      findsOneWidget,
    );
    expect(repository.all().single['html'], originalHtml);
    state.dispose();
  });
}
