import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/assistant_state.dart';
import 'package:personal_assistant/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_tts'),
          (_) async => 1,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AssistantState.device, (_) async => true);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'), null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AssistantState.device, null);
  });
  testWidgets(
    'primary navigation can enter and revisit persisted memories without build-phase notification',
    (tester) async {
      tester.view.physicalSize = const Size(382, 754);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      // This test covers Home navigation, not secure-setting hydration; seed
      // the app-lock gate explicitly so secure-storage timing cannot hide Home.
      final state = AssistantState()
        ..ready = true
        ..appLockConfigurationReady = true
        ..onboarded = true;
      await state.local.load();
      await state.remember('Synthetic navigation memory');
      await tester.pumpWidget(AssistantApp(state: state));
      await tester.pumpAndSettle();
      expect(find.text('Here when you need me'), findsOneWidget);
      expect(find.byTooltip('Start a voice conversation'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Open tasks'),
        280,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Open tasks'), findsOneWidget);

      // Actions lives in the grouped drawer; the dock reserves its center slot for Voice.
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      expect(find.text('TOOLS'), findsOneWidget);
      await tester.tap(find.text('Actions').last);
      await tester.pumpAndSettle();
      expect(find.text('Prepare a reminder'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Entering Actions');

      for (final entry in [
        ('Skills & actions', 'What the team can and can’t do'),
        ('Message & social drafts', 'Write it here, send it yourself'),
      ]) {
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(entry.$1).last);
        await tester.pumpAndSettle();
        final screenEvidence = find.text(entry.$2);
        await tester.scrollUntilVisible(
          screenEvidence,
          240,
          // Skills now contains a horizontal TextField scrollable; target the page list.
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(screenEvidence, findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'Entering ${entry.$1}');
      }

      var chatUsesDrawer = false;
      for (final label in ['Chat', 'Memory', 'Settings', 'Home', 'Memory']) {
        if (chatUsesDrawer) {
          await tester.tap(find.byTooltip('Open navigation menu'));
          await tester.pumpAndSettle();
          if (label == 'Memory' || label == 'Settings') {
            await _scrollDrawerUntilVisible(tester, label);
          }
          await tester.tap(find.text(label).last);
        } else {
          await tester.tap(find.text(label).last);
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Entering $label');
        if (label == 'Chat') {
          expect(find.text('Chat'), findsNothing);
          expect(find.byTooltip('Start a voice conversation'), findsNothing);
          chatUsesDrawer = true;
        } else if (label == 'Memory') {
          expect(find.text('Synthetic navigation memory'), findsOneWidget);
          chatUsesDrawer = false;
        }
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      state.dispose();
    },
  );
}

Future<void> _scrollDrawerUntilVisible(
  WidgetTester tester,
  String label,
) async {
  final list = find.byKey(const Key('navigation-drawer-list'));
  final item = find.descendant(of: list, matching: find.text(label));
  final screenSize = tester.view.physicalSize / tester.view.devicePixelRatio;
  final screen = Offset.zero & screenSize;
  for (var attempt = 0; attempt < 12; attempt++) {
    if (item.evaluate().isNotEmpty && screen.contains(tester.getCenter(item))) {
      return;
    }
    await tester.drag(list, const Offset(0, -220));
    await tester.pumpAndSettle();
  }
  expect(item, findsOneWidget);
  expect(screen.contains(tester.getCenter(item)), isTrue);
}
