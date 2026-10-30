import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/contact_picker_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('personal_assistant/device');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets(
    'one contact is read only after the explicit picker tap and reviewed locally',
    (tester) async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return {'display_name': 'Asha Rao', 'phone_number': '+91 98765 43210'};
      });
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ContactPickerScreen())),
      );
      expect(calls, isEmpty);
      expect(
        find.textContaining('does not scan your address book'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('pick-one-contact')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(calls.single.method, 'pick_one_contact');
      expect(calls.single.arguments, isNull);
      expect(find.text('Review selected contact'), findsOneWidget);
      expect(find.textContaining('Name: Asha Rao'), findsOneWidget);
      expect(find.textContaining('not saved or sent anywhere'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Asha Rao'), findsOneWidget);
      expect(calls.length, 1);
    },
  );

  testWidgets('canceled picker leaves no selection or network action', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ContactPickerScreen())),
    );
    await tester.tap(find.byKey(const Key('pick-one-contact')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(calls.map((call) => call.method), ['pick_one_contact']);
    expect(
      find.text('Selection canceled. No contact was kept.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('clear-selected-contact')), findsNothing);
  });
}
