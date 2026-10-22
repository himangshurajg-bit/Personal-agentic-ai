import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/home_orb.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('only the bundled orb page is an allowed WebView navigation', () {
    expect(
      homeOrbAllowsNavigation(
        'file:///android_asset/flutter_assets/assets/home_orb.html',
      ),
      isTrue,
    );
    expect(homeOrbAllowsNavigation('https://example.com/'), isFalse);
    expect(
      homeOrbAllowsNavigation(
        'file:///android_asset/flutter_assets/assets/home_orb.html?redirect=1',
      ),
      isFalse,
    );
    expect(homeOrbAllowsNavigation('javascript:alert(1)'), isFalse);
  });

  test('bundled orb is local-only and has a decorative disclosure', () async {
    final html = await rootBundle.loadString('assets/home_orb.html');
    expect(html, contains("default-src 'none'"));
    expect(html, contains("connect-src 'none'"));
    expect(html, contains('prefers-reduced-motion: reduce'));
    expect(html, contains('mountHeroOrb();'));
    expect(html, contains('DECORATIVE ART'));
    expect(html, isNot(contains('<script src=')));
    expect(html, isNot(contains('https://')));
    expect(html, isNot(contains('fetch(')));
    expect(homeOrbDisclosure, contains('does not show AI activity'));
  });

  testWidgets('home orb exposes its decorative disclosure and fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DecorativeHomeOrb())),
    );
    expect(find.text('Home orb'), findsOneWidget);
    expect(find.text(homeOrbDisclosure), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome_rounded), findsOneWidget);
  });
}
