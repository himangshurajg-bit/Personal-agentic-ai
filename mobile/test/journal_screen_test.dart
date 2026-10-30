import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/assistant_features_screen.dart';
import 'package:personal_assistant/assistant_state.dart';
import 'package:personal_assistant/journal_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Future<AssistantState> readyState() async {
    final state = AssistantState();
    await state.local.load();
    return state;
  }

  testWidgets('journal can create, edit and delete local entries', (
    tester,
  ) async {
    final state = await readyState();
    await tester.pumpWidget(MaterialApp(home: JournalScreen(state: state)));
    expect(find.text('Your entries will appear here.'), findsOneWidget);
    expect(find.textContaining('never sent to AI or synced'), findsOneWidget);

    await tester.tap(find.text('Write an entry'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'First reflection');
    await tester.tap(find.text('Save entry'));
    await tester.pumpAndSettle();
    expect(find.text('First reflection'), findsOneWidget);
    expect(state.local.rows('journal_entries'), hasLength(1));

    await tester.tap(find.text('First reflection'));
    await tester.pumpAndSettle();
    expect(find.text('Edit entry'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Edited reflection');
    await tester.tap(find.text('Save entry'));
    await tester.pumpAndSettle();
    expect(find.text('Edited reflection'), findsOneWidget);
    expect(find.text('First reflection'), findsNothing);
    expect(state.local.rows('journal_entries'), hasLength(1));

    await tester.tap(find.byTooltip('Entry actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(find.text('Your entries will appear here.'), findsOneWidget);
    expect(state.local.rows('journal_entries'), isEmpty);
  });

  testWidgets('journal is reachable from the assistant tools tabs', (
    tester,
  ) async {
    final state = await readyState();
    await tester.pumpWidget(
      MaterialApp(
        home: FeaturesScreen(
          state: state,
          initialTab: 8,
          onReminder: (context, value) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Your journal'), findsOneWidget);
    expect(find.text('Write an entry'), findsOneWidget);
  });
}
