import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/assistant_features_screen.dart';
import 'package:personal_assistant/assistant_state.dart';
import 'package:personal_assistant/wifi_settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('personal_assistant/device');

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  testWidgets('reads only enabled state after explicit tap', (tester) async {
    MethodCall? call;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
          call = methodCall;
          return {'enabled': true};
        });
    await tester.pumpWidget(const MaterialApp(home: WifiSettingsScreen()));

    expect(find.text('Status not checked'), findsOneWidget);
    expect(call, isNull);
    await tester.tap(find.byKey(const Key('wifi-check')));
    await tester.pumpAndSettle();

    expect(call?.method, 'read_wifi_status');
    expect(find.text('Wi-Fi is enabled'), findsOneWidget);
    expect(find.textContaining('network name'), findsOneWidget);
  });

  testWidgets(
    'opens settings only after explicit tap and avoids toggle claim',
    (tester) async {
      MethodCall? call;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
            call = methodCall;
            return {'opened': true, 'destination': 'connectivity_panel'};
          });
      await tester.pumpWidget(const MaterialApp(home: WifiSettingsScreen()));
      expect(call, isNull);
      await tester.tap(find.byKey(const Key('wifi-open-settings')));
      await tester.pumpAndSettle();

      expect(call?.method, 'open_wifi_settings');
      expect(
        find.textContaining('Android opened connectivity settings'),
        findsOneWidget,
      );
      expect(find.textContaining('Wi-Fi changed'), findsNothing);
    },
  );

  testWidgets('reports platform failure without claiming success', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(
            code: 'unavailable',
            message: 'Android could not open Wi-Fi settings.',
          );
        });
    await tester.pumpWidget(const MaterialApp(home: WifiSettingsScreen()));
    await tester.tap(find.byKey(const Key('wifi-open-settings')));
    await tester.pumpAndSettle();

    expect(find.text('Android could not open Wi-Fi settings.'), findsOneWidget);
    expect(
      find.textContaining('Android opened connectivity settings'),
      findsNothing,
    );
  });

  testWidgets('Wi-Fi is its own assistant-tools tab', (tester) async {
    final state = AssistantState();
    await state.local.load();
    await tester.pumpWidget(
      MaterialApp(
        home: FeaturesScreen(
          state: state,
          onReminder: _ignoreReminder,
          initialTab: 11,
        ),
      ),
    );
    expect(find.text('Wi-Fi status'), findsOneWidget);
    expect(find.byKey(const Key('wifi-check')), findsOneWidget);
  });
}

Future<void> _ignoreReminder(BuildContext context, String value) async {}
