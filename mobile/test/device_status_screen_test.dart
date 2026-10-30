import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/assistant_state.dart';
import 'package:personal_assistant/device_status_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('device status is read only after an explicit refresh tap', (
    tester,
  ) async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AssistantState.device, (call) async {
          calls++;
          expect(call.method, 'read_device_status_snapshot');
          return <String, Object?>{
            'local_time': '2026-10-30T12:00:00+05:30',
            'time_zone': 'Asia/Kolkata',
            'android_release': '16',
            'android_sdk': 36,
            'security_patch': '2026-10-05',
            'app_version': '1.0.0',
            'app_build': 17,
            'uptime_ms': 120000,
            'storage_total_bytes': 1024 * 1024 * 1024,
            'storage_available_bytes': 512 * 1024 * 1024,
            'memory_total_bytes': 8 * 1024 * 1024 * 1024,
            'memory_available_bytes': 4 * 1024 * 1024 * 1024,
            'display_width_px': 1080,
            'display_height_px': 2400,
            'display_density_dpi': 420,
            'display_refresh_hz': 120.0,
            'locale': 'en-IN',
            'ringer_mode': 'normal',
            'system_theme': 'dark',
            'thermal_status': 'none',
            'battery_saver': false,
            'brightness_level': 128,
            'brightness_percent': 50,
            'notifications_enabled': true,
            'battery_percent': 75,
            'battery_status': 'charging',
            'battery_health': 'good',
            'battery_temperature_c': 32.0,
            'battery_voltage_mv': 4000,
            'battery_chemistry': 'Li-ion',
          };
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AssistantState.device, null);
    });

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DeviceStatusScreen())),
    );
    expect(calls, 0);
    expect(
      find.text('Tap refresh to read the current device status.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Refresh device status'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Android'), findsOneWidget);
    expect(find.text('16 (API 36)'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Battery'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('75%'), findsOneWidget);
  });
}
