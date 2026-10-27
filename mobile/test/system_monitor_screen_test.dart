import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/system_monitor_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('personal_assistant/device');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return <String, Object?>{
            'cpu_percent': 42,
            'memory_available_bytes': 1024 * 1024 * 1024,
            'memory_total_bytes': 2 * 1024 * 1024 * 1024,
            'storage_free_bytes': 3 * 1024 * 1024 * 1024,
            'storage_total_bytes': 8 * 1024 * 1024 * 1024,
            'network_received_bytes': 512,
            'network_sent_bytes': -1,
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('shows a read-only metrics snapshot and refreshes on demand', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SystemMonitorScreen())),
    );
    await tester.pumpAndSettle();

    expect(calls.map((call) => call.method), ['read_system_metrics']);
    expect(find.text('CPU busy'), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
    expect(find.text('1.0 GB free'), findsOneWidget);
    expect(find.text('512 B'), findsOneWidget);
    expect(find.text('Unavailable'), findsOneWidget);
    expect(
      find.textContaining('Device-wide total since boot'),
      findsNWidgets(2),
    );
    expect(
      find.textContaining('nothing is tracked in the background'),
      findsOneWidget,
    );

    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(calls.map((call) => call.method), [
      'read_system_metrics',
      'read_system_metrics',
    ]);
  });
}
