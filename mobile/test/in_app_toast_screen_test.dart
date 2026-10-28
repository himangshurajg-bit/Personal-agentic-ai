import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/in_app_toast_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('toast text is bounded, non-empty and printable', () {
    expect(isValidInAppToastText('Saved'), isTrue);
    expect(isValidInAppToastText('  '), isFalse);
    expect(isValidInAppToastText('line one\nline two'), isFalse);
    expect(isValidInAppToastText('x' * 121), isFalse);
    expect(isValidInAppToastText('x' * 120), isTrue);
    expect(isValidInAppToastText('ok\u0085no'), isFalse);
  });

  testWidgets('shows exact text only after explicit review approval', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: InAppToastScreen()),
    );
    expect(find.byType(SnackBar), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byKey(const ValueKey('review-in-app-toast')))
          .onPressed,
      isNull,
    );

    const message = 'Build is ready';
    await tester.enterText(
      find.byKey(const ValueKey('in-app-toast-text')),
      message,
    );
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);

    await tester.tap(find.byKey(const ValueKey('review-in-app-toast')));
    await tester.pumpAndSettle();
    expect(find.text('Review in-app message'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(AlertDialog), matching: find.text(message)),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);

    await tester.tap(find.byKey(const ValueKey('cancel-in-app-toast')));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);

    await tester.tap(find.byKey(const ValueKey('review-in-app-toast')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-in-app-toast')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.descendant(of: find.byType(SnackBar), matching: find.text(message)),
      findsOneWidget,
    );
    expect(find.text('Shown briefly in this app only.'), findsOneWidget);
  });
}
