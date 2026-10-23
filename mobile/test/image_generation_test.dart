import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_assistant/image_generation_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const tinyPngBase64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jXioAAAAASUVORK5CYII=';

  testWidgets('image request sends only typed prompt and displays preview', (
    tester,
  ) async {
    http.Request? observed;
    final png = base64Decode(tinyPngBase64);
    await tester.pumpWidget(
      MaterialApp(
        home: ImageGenerationScreen(
          endpoint: 'http://127.0.0.1:8766',
          token: 'service-token-that-is-long-enough-for-test',
          clientFactory: () => MockClient((request) async {
            observed = request;
            return http.Response.bytes(
              png,
              200,
              headers: {'content-type': 'image/png'},
            );
          }),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'A fox under blue trees');
    await tester.tap(find.text('Generate image'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(observed?.url.path, '/images/generate');
    expect(observed?.method, 'POST');
    expect(observed?.headers['authorization'], startsWith('Bearer '));
    expect(jsonDecode(observed!.body), {'prompt': 'A fox under blue trees'});
    expect(jsonDecode(observed!.body).keys, {'prompt'});
    expect(find.byType(Image), findsOneWidget);
    expect(
      find.text('Image generation is not configured on the private service.'),
      findsNothing,
    );
  });

  testWidgets('disabled image provider explains that no image was generated', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ImageGenerationScreen(
          endpoint: 'http://127.0.0.1:8766',
          token: 'service-token-that-is-long-enough-for-test',
          clientFactory: () =>
              MockClient((_) async => http.Response('disabled', 503)),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'a mountain');
    await tester.tap(find.text('Generate image'));
    await tester.pumpAndSettle();
    expect(
      find.text('Image generation is not configured on the private service.'),
      findsOneWidget,
    );
    expect(find.byType(Image), findsNothing);
  });
}
