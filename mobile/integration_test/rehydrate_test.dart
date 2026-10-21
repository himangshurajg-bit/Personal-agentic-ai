import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:personal_assistant/assistant_state.dart';
import 'package:personal_assistant/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('API36 restart retains local state without provider', (
    tester,
  ) async {
    final s = AssistantState();
    await s.initialize();
    expect(s.assistantName, 'API36 Test assistant');
    expect(s.note, 'Synthetic local-only note');
    expect(s.local.rows('memories'), hasLength(1));
    expect(s.local.rows('tasks'), hasLength(1));
    expect(s.local.rows('attempts'), hasLength(1));
    expect(s.local.studyDecks.single['title'], 'Synthetic API36 deck');
    expect(s.local.rows('flashcards').single['review_count'], 1);
    expect(s.local.rows('study_reviews'), hasLength(1));
    expect(s.local.rows('actions').single['status'], 'scheduled');
    expect(s.local.searchChats('velocity'), isNotEmpty);
    await tester.pumpWidget(AssistantApp(state: s));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
