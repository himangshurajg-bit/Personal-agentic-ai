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
      final state = AssistantState();
      await state.initialize();
      await state.finishOnboarding();
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

      for (final label in ['Chat', 'Memory', 'Settings', 'Home', 'Memory']) {
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Entering $label');
        if (label == 'Memory') {
          expect(find.text('Synthetic navigation memory'), findsOneWidget);
        }
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      state.dispose();
    },
  );
}
