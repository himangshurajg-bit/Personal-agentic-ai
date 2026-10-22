import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/app_lock.dart';
import 'package:personal_assistant/assistant_state.dart';
import 'package:personal_assistant/main.dart';

class FakeAuthenticator implements DeviceAuthenticator {
  final List<Object> outcomes;
  FakeAuthenticator(this.outcomes);
  int calls = 0;
  @override
  Future<bool> authenticate() async {
    final outcome = outcomes[calls++];
    if (outcome is Exception || outcome is Error) throw outcome;
    return outcome as bool;
  }
}

class ControlledAuthenticator implements DeviceAuthenticator {
  final Completer<bool> result = Completer<bool>();
  bool called = false;

  @override
  Future<bool> authenticate() {
    called = true;
    return result.future;
  }
}

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

  test(
    'unknown secure lock settings stay gated during initialization retry',
    () {
      final state = AssistantState()..ready = true;
      expect(state.appLockGateVisible, isTrue);
      state.ready = false;
      expect(state.appLockGateVisible, isTrue);
      state.appLockConfigurationReady = true;
      expect(state.appLockGateVisible, isFalse);
      state.dispose();
    },
  );

  test('enabling and disabling require successful OS authentication', () async {
    final auth = FakeAuthenticator([
      false,
      StateError('unavailable'),
      true,
      false,
      true,
    ]);
    final state = AssistantState(authenticator: auth);
    await state.initialize();

    expect(await state.setAppLockEnabled(true), isFalse);
    expect(await state.storage.read(key: 'app_lock_enabled'), isNull);
    expect(state.appLockEnabled, isFalse);

    expect(await state.setAppLockEnabled(true), isFalse);
    expect(await state.storage.read(key: 'app_lock_enabled'), isNull);

    expect(await state.setAppLockEnabled(true), isTrue);
    expect(await state.storage.read(key: 'app_lock_enabled'), 'yes');
    expect(state.appLockEnabled, isTrue);

    expect(await state.setAppLockEnabled(false), isFalse);
    expect(await state.storage.read(key: 'app_lock_enabled'), 'yes');
    expect(state.appLockEnabled, isTrue);

    expect(await state.setAppLockEnabled(false), isTrue);
    expect(await state.storage.read(key: 'app_lock_enabled'), isNull);
    expect(state.appLockEnabled, isFalse);
    state.dispose();
  });

  test(
    'relaunch starts locked; cancelled unlock stays locked; success unlocks',
    () async {
      final setup = AssistantState(authenticator: FakeAuthenticator([true]));
      await setup.initialize();
      expect(await setup.setAppLockEnabled(true), isTrue);
      setup.dispose();

      final auth = FakeAuthenticator([false, true, true]);
      final reopened = AssistantState(authenticator: auth);
      await reopened.initialize();
      expect(reopened.appLockEnabled, isTrue);
      expect(reopened.appLockGateVisible, isTrue);
      expect(await reopened.unlockApp(), isFalse);
      expect(reopened.appLockGateVisible, isTrue);
      expect(await reopened.unlockApp(), isTrue);
      expect(reopened.appLockGateVisible, isFalse);
      reopened.lockApp();
      expect(reopened.appLockGateVisible, isTrue);
      expect(await reopened.setAppLockEnabled(false), isTrue);
      reopened.dispose();
    },
  );

  testWidgets(
    'authentication focus loss does not immediately relock after success',
    (tester) async {
      final setup = AssistantState(authenticator: FakeAuthenticator([true]));
      await setup.initialize();
      await setup.finishOnboarding();
      expect(await setup.setAppLockEnabled(true), isTrue);
      setup.dispose();

      final auth = ControlledAuthenticator();
      final state = AssistantState(authenticator: auth);
      await state.initialize();
      await tester.pumpWidget(AssistantApp(state: state));
      await tester.pumpAndSettle();
      expect(find.text('Your assistant is locked'), findsOneWidget);

      await tester.tap(find.text('Unlock'));
      await tester.pump();
      expect(auth.called, isTrue);

      // Android's biometric/device-credential prompt can temporarily take focus.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      auth.result.complete(true);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text('Your assistant is locked'), findsNothing);
      expect(find.text('Home'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      state.dispose();
    },
  );

  testWidgets('app content is gated on background return until auth succeeds', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(382, 754);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final auth = FakeAuthenticator([true, false, true, true]);
    final state = AssistantState(authenticator: auth);
    await state.initialize();
    await state.finishOnboarding();
    expect(await state.setAppLockEnabled(true), isTrue);
    await tester.pumpWidget(AssistantApp(state: state));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Your assistant is locked'), findsOneWidget);
    expect(find.text('Home'), findsNothing);

    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Your assistant is locked'), findsOneWidget);
    expect(
      find.text(
        'Authentication was cancelled or unavailable. Your app stays locked.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Your assistant is locked'), findsNothing);
    expect(find.text('Home'), findsOneWidget);
    expect(await state.setAppLockEnabled(false), isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    state.dispose();
  });
}
