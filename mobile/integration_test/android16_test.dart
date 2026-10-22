import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:personal_assistant/assistant_state.dart';
import 'package:personal_assistant/main.dart';

Future<void> pumpRouteFrames(WidgetTester tester) async {
  // Home includes a continuously animated orb, so pump fixed frames instead of
  // waiting for the entire widget tree to become idle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'API36 native storage, safe modes, navigation and action boundary',
    (tester) async {
      void phase(String name) => debugPrint('API36_PHASE: $name');

      const secure = FlutterSecureStorage();
      phase('clear isolated secure storage');
      // Isolated disposable emulator; never run against the owner's existing app data.
      await secure.deleteAll();
      final s = AssistantState();
      await s.initialize();
      phase('native storage and local state initialized');
      await s.setAssistantName('API36 Test assistant');
      await s.finishOnboarding();
      await s.saveNote('Synthetic local-only note');
      await s.local.writeChat('test36', [
        {
          'role': 'user',
          'text': 'Synthetic velocity practice · অসমীয়া পাঠ · हिन्दी पढ़ाई · Hinglish kal study',
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
        (await restored.local.searchChats('VELOCITY')).single['conversation'],
        'test36',
      );
      expect(
        (await restored.local.searchChats('অসমীয়া')).single['conversation'],
        'test36',
      );
      expect(restored.local.lastSearchUsedRust, isTrue);
      expect(
        (await restored.local.searchChats('पढ़ाई')).single['conversation'],
        'test36',
      );
      expect(restored.local.lastSearchUsedRust, isTrue);
      expect(
        (await restored.local.searchChats('Hinglish')).single['conversation'],
        'test36',
      );
      expect(restored.local.lastSearchUsedRust, isTrue);
      expect(restored.local.rows('memories'), hasLength(1));
      expect(restored.local.rows('tasks'), hasLength(1));
      expect(restored.local.rows('attempts'), hasLength(1));
      expect(restored.local.studyDecks.single['title'], 'Synthetic API36 deck');
      expect(restored.local.cardsForDeck(deckId).single['review_count'], 1);
      expect(restored.local.rows('study_reviews'), hasLength(1));
      phase('persisted records restored and checked');
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
      phase('native device, auth, and voice safety checks passed');
      final bad = await AssistantState.device.invokeMapMethod('execute', {
        'kind': 'shell',
        'command': 'never-run',
      });
      expect(bad!['result'], 'failed');
      await s.send('No network should be used');
      expect(s.error, contains('Offline AI is not installed'));
      phase('offline mode failed closed without a network');
      await tester.pumpWidget(AssistantApp(state: s));
      await pumpRouteFrames(tester);
      expect(find.text('API36 Test assistant'), findsOneWidget);
      phase('initial app frame settled');
      // Exercise the labels the glass dock actually exposes; Actions opens
      // automations and Memory opens the combined memory/library destination.
      for (final label in [
        'Chat',
        'Actions',
        'Memory',
        'Settings',
        'Home',
      ]) {
        phase('navigation tap started: $label');
        await tester.tap(find.text(label).last);
        phase('navigation tap completed: $label');
        await pumpRouteFrames(tester);
        phase('navigation settled: $label');
        expect(tester.takeException(), isNull);
      }
      phase('glass dock navigation passed');
      final draft = await s.prepareAction({
        'kind': 'reminder',
        'title': 'Synthetic API36 test',
        'at_ms': DateTime.now()
            .add(const Duration(days: 1))
            .millisecondsSinceEpoch,
      });
      // CI grants only notifications after asserting microphone was not granted.
      phase('reminder action prepared; executing approved local action');
      final receipt = await s.executeApproved(draft['id']);
      expect(receipt['result'], 'scheduled');
      await expectLater(
        s.executeApproved(draft['id']),
        throwsA(isA<ServiceException>()),
      );
      await pumpRouteFrames(tester);
      phase('all Android 16 integration assertions passed');
    },
  );
}
