import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:personal_assistant/assistant_state.dart';
import 'package:personal_assistant/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'API36 native storage, safe modes, navigation and action boundary',
    (tester) async {
      const secure = FlutterSecureStorage();
      // Isolated disposable emulator; never run against the owner's existing app data.
      await secure.deleteAll();
      final s = AssistantState();
      await s.initialize();
      await s.setAssistantName('API36 Test assistant');
      await s.finishOnboarding();
      await s.saveNote('Synthetic local-only note');
      await s.local.writeChat('test36', [
        {
          'role': 'user',
          'text': 'Synthetic velocity practice',
          'state': 'complete',
        },
      ]);
      await s.remember('Synthetic blue preference', scope: 'test36');
      await s.local.task('Synthetic revision task');
      await s.local.attempt({
        'topic': 'velocity',
        'problem': '2/1',
        'answer': '2',
        'feedback': 'synthetic',
        'result': 'not checked',
      });
      final deckId = await s.local.createStudyDeck('Synthetic API36 deck');
      final cardId = await s.local.createFlashcard(
        deckId,
        'Synthetic question',
        'Synthetic answer',
      );
      await s.local.reviewFlashcard(cardId, 'good');
      final restored = AssistantState();
      await restored.initialize();
      expect(restored.note, 'Synthetic local-only note');
      expect(
        restored.local.searchChats('VELOCITY').single['conversation'],
        'test36',
      );
      expect(restored.local.rows('memories'), hasLength(1));
      expect(restored.local.rows('tasks'), hasLength(1));
      expect(restored.local.rows('attempts'), hasLength(1));
      expect(restored.local.studyDecks.single['title'], 'Synthetic API36 deck');
      expect(restored.local.cardsForDeck(deckId).single['review_count'], 1);
      expect(restored.local.rows('study_reviews'), hasLength(1));
      final status = await AssistantState.device.invokeMapMethod(
        'device_status',
      );
      expect(status!['sdk'], 36);
      expect(status['microphone_granted'], false);
      // Exercise the registered native local_auth bridge without prompting for enrollment.
      expect(await LocalAuthentication().isDeviceSupported(), isA<bool>());
      await expectLater(
        AssistantState.device.invokeMethod('voice_start', {
          'mode': 'online',
          'locale': 'en-IN',
          'approved_online': false,
        }),
        throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'approval'),
        ),
      );
      await expectLater(
        AssistantState.device.invokeMethod('voice_start', {
          'mode': 'offline',
          'locale': 'invalid',
        }),
        throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'invalid'),
        ),
      );
      final bad = await AssistantState.device.invokeMapMethod('execute', {
        'kind': 'shell',
        'command': 'never-run',
      });
      expect(bad!['result'], 'failed');
      await s.send('No network should be used');
      expect(s.error, contains('Offline AI is not installed'));
      await tester.pumpWidget(AssistantApp(state: s));
      await tester.pumpAndSettle();
      expect(find.text('API36 Test assistant'), findsOneWidget);
      for (final label in [
        'Chat',
        'Automations',
        'Memory & Library',
        'Settings',
        'Home',
      ]) {
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      final draft = await s.prepareAction({
        'kind': 'reminder',
        'title': 'Synthetic API36 test',
        'at_ms': DateTime.now()
            .add(const Duration(days: 1))
            .millisecondsSinceEpoch,
      });
      // CI grants only notifications after asserting microphone was not granted.
      final receipt = await s.executeApproved(draft['id']);
      expect(receipt['result'], 'scheduled');
      await expectLater(
        s.executeApproved(draft['id']),
        throwsA(isA<ServiceException>()),
      );
      await tester.pumpAndSettle();
    },
  );
}
