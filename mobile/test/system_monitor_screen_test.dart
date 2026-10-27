import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/system_monitor_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('personal_assistant/device');
  final calls = <MethodCall>[];
  var readCount = 0;

  setUp(() {
    calls.clear();
    readCount = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          readCount++;
          return <String, Object?>{
            'cpu_percent': readCount == 1 ? 42 : 40 + readCount * 10,
            'memory_available_bytes': readCount == 1
                ? 1024 * 1024 * 1024
                : 512 * 1024 * 1024,
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

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      250,
      scrollable: find.byType(Scrollable).first,
    );
  }

  Future<void> scrollToTop(WidgetTester tester) async {
    await tester.drag(find.byType(ListView).first, const Offset(0, 1200));
    await tester.pumpAndSettle();
  }

  testWidgets('shows a snapshot and refreshes only on demand', (tester) async {
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
      find.textContaining('never saved or sampled in the background'),
      findsOneWidget,
    );
    await scrollTo(
      tester,
      find.text('0 captured samples · in memory only, up to 60 samples'),
    );
    expect(
      find.text('0 captured samples · in memory only, up to 60 samples'),
      findsOneWidget,
    );

    await scrollToTop(tester);
    await tester.tap(find.text('Refresh snapshot'));
    await tester.pumpAndSettle();
    expect(calls.map((call) => call.method), [
      'read_system_metrics',
      'read_system_metrics',
    ]);
    await scrollTo(
      tester,
      find.text('0 captured samples · in memory only, up to 60 samples'),
    );
    expect(
      find.text('0 captured samples · in memory only, up to 60 samples'),
      findsOneWidget,
    );
  });

  testWidgets('captures bounded session history only on explicit taps', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SystemMonitorScreen())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Capture history sample'));
    await tester.pumpAndSettle();
    await scrollTo(
      tester,
      find.text('1 captured sample · in memory only, up to 60 samples'),
    );
    expect(
      find.text('1 captured sample · in memory only, up to 60 samples'),
      findsOneWidget,
    );
    expect(find.text('Capture another sample to see a trend.'), findsOneWidget);

    await scrollToTop(tester);
    await tester.tap(find.text('Refresh snapshot'));
    await tester.pumpAndSettle();
    await scrollTo(
      tester,
      find.text('1 captured sample · in memory only, up to 60 samples'),
    );
    expect(
      find.text('1 captured sample · in memory only, up to 60 samples'),
      findsOneWidget,
    );

    await scrollToTop(tester);
    await tester.tap(find.text('Capture history sample'));
    await tester.pumpAndSettle();
    await scrollTo(
      tester,
      find.text('2 captured samples · in memory only, up to 60 samples'),
    );
    expect(
      find.text('2 captured samples · in memory only, up to 60 samples'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('system-monitor-history-chart')),
      findsOneWidget,
    );
    expect(calls.length, 4);

    await scrollTo(tester, find.byKey(const ValueKey('clear-monitor-history')));
    await tester.tap(find.byKey(const ValueKey('clear-monitor-history')));
    await tester.pumpAndSettle();
    expect(
      find.text('0 captured samples · in memory only, up to 60 samples'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('system-monitor-history-chart')),
      findsNothing,
    );
    expect(calls.length, 4);
  });
}
