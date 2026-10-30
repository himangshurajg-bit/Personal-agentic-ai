import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:personal_assistant/assistant_state.dart';
import 'package:personal_assistant/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('API36 restart retains local state without provider', (
    tester,
  ) async {
    void phase(String name) => debugPrint('API36_REHYDRATE_PHASE: $name');
    phase('state initialization started');
    final s = AssistantState();
    await s.initialize();
    phase('state initialization completed');
    expect(s.assistantName, 'API36 Test assistant');
    expect(s.note, 'Synthetic local-only note');
    expect(s.local.rows('memories'), hasLength(1));
    expect(s.local.rows('tasks'), hasLength(1));
    expect(s.local.rows('attempts'), hasLength(1));
    expect(s.local.studyDecks.single['title'], 'Synthetic API36 deck');
    expect(s.local.rows('flashcards').single['review_count'], 1);
    expect(s.local.rows('study_reviews'), hasLength(1));
    expect(s.local.rows('actions').single['status'], 'scheduled');
    phase('persisted records checked');
    expect(await s.local.searchChats('velocity'), isNotEmpty);
    expect(s.local.lastSearchUsedRust, isTrue);
    phase('native search completed');
    await tester.pumpWidget(AssistantApp(state: s));
    phase('assistant widget mounted');
    // The home orb animates continuously, so pump bounded frames instead of settling.
    await tester.pump();
    phase('first frame pumped');
    await tester.pump(const Duration(milliseconds: 500));
    phase('bounded animation frame pumped');
    expect(tester.takeException(), isNull);
    phase('test assertions completed');
  });
}
