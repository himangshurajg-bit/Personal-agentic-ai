import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/main.dart' show Shell;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Back returns to Home, then exits from Home', (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var exitRequests = 0;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemNavigator.pop') exitRequests++;
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        initialRoute: '/home',
        routes: {
          '/home': (_) => const Shell(
            title: 'Home',
            primaryNavigation: false,
            child: Text('home-page'),
          ),
          '/settings': (_) =>
              const Shell(title: 'Settings', child: Text('settings-page')),
        },
      ),
    );
    await tester.pumpAndSettle();

    navigatorKey.currentState!.pushNamed('/settings');
    await tester.pumpAndSettle();
    expect(find.text('settings-page'), findsOneWidget);
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('settings-page'), findsOneWidget);
    expect(find.text('home-page'), findsNothing);

    await tester.tap(find.byTooltip('Back to Home'));
    await tester.pumpAndSettle();
    expect(find.text('home-page'), findsOneWidget);
    expect(exitRequests, 0);

    navigatorKey.currentState!.pushNamed('/settings');
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('home-page'), findsOneWidget);
    expect(exitRequests, 0);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(exitRequests, 1);
  });
}
