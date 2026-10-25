import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/assistant_state.dart';
import 'package:personal_assistant/main.dart';
import 'package:personal_assistant/phone_screens.dart';
import 'package:personal_assistant/readable_math.dart';

const _workedExample = r'''## Worked example

Question: An aqueous solution of a titanium(III) complex, $[\text{Ti}(\text{H}_2\text{O})_6]^{3+}$, absorbs light with a wavelength ($\lambda$) of $500\ \text{nm}$. Calculate the crystal field splitting energy ($\Delta_0$) in Joules per ion and in $\text{kJ/mol}$. (Given: Planck's constant $h = 6.626 \times 10^{-34}\ \text{J}\cdot\text{s}$, Speed of light $c = 3 \times 10^8\ \text{m/s}$, Avogadro's number $N_A = 6.022 \times 10^{23}\ \text{mol}^{-1}$.)

1. Relate energy to wavelength: $$\Delta E = \frac{hc}{\lambda}$$
2. Convert wavelength: $500\ \text{nm} = 500 \times 10^{-9}\ \text{m}$.
3. Per ion: $$\Delta E = \frac{(6.626 \times 10^{-34}\ \text{J}\cdot\text{s})(3 \times 10^8\ \text{m/s})}{500 \times 10^{-9}\ \text{m}} = 3.9756 \times 10^{-19}\ \text{J per ion}$$
4. Per mole: $$\Delta_0 = \Delta E \times N_A \approx 239{,}415\ \text{J/mol} \approx 239.4\ \text{kJ/mol}$$

- Keep the significant figures and units visible.
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      (_) async => 1,
    );
    messenger.setMockMethodCallHandler(
      AssistantState.device,
      (_) async => true,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      (_) async => null,
    );
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      null,
    );
    messenger.setMockMethodCallHandler(AssistantState.device, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      null,
    );
  });

  test(
    'converts screenshot-style chemistry and energy TeX to readable text',
    () {
      final formatted = ReadableMath.formatMarkdown(_workedExample);

      expect(formatted, contains('## Worked example'));
      expect(formatted, contains('1. Relate energy to wavelength'));
      expect(formatted, contains('[Ti(H₂O)₆]³⁺'));
      expect(formatted, contains('λ'));
      expect(formatted, contains('Δ₀'));
      expect(formatted, contains('Δ E = (hc)/(λ)'));
      expect(formatted, contains('6.626 × 10⁻³⁴ J·s'));
      expect(formatted, contains('3.9756 × 10⁻¹⁹ J per ion'));
      expect(formatted, contains('239.4 kJ/mol'));
      expect(formatted, isNot(contains(r'\text')));
      expect(formatted, isNot(contains(r'\frac')));
      expect(formatted, isNot(contains(r'\lambda')));
      expect(formatted, isNot(contains(r'\times')));
      expect(formatted, isNot(contains(r'$$')));
    },
  );

  test('preserves code samples and ordinary currency text', () {
    const source = r'''Price $5 and code `\Delta_0`.
```tex
\frac{a}{b}
```
Math: $\Delta_0 = 5$''';
    final formatted = ReadableMath.formatMarkdown(source);
    expect(formatted, contains(r'Price $5 and code `\Delta_0`.'));
    expect(
      formatted,
      contains(r'''```tex
\frac{a}{b}
```'''),
    );
    expect(formatted, contains('Math: Δ₀ = 5'));
  });

  testWidgets('chat message renders formulas in readable Markdown', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = AssistantState();
    await state.initialize();
    await state.selectConversation('readable-math-chat-test', load: false);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: ChatScreen(state: state),
        ),
      ),
    );
    await tester.pumpAndSettle();
    state.messages.add({
      'role': 'assistant',
      'text': _workedExample,
      'state': 'complete',
    });
    state.notifyListeners();
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(find.textContaining('Worked example'), findsOneWidget);
    expect(find.textContaining('[Ti(H₂O)₆]³⁺'), findsOneWidget);
    expect(find.textContaining('3.9756 × 10⁻¹⁹ J per ion'), findsOneWidget);
    expect(find.textContaining(r'\frac'), findsNothing);
    expect(find.textContaining(r'\text'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    state.dispose();
  });

  testWidgets('Study Whiteboard renders the same readable math and Markdown', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = AssistantState();
    await state.initialize();
    await state.selectConversation(
      'readable-math-whiteboard-test',
      load: false,
    );
    final lessonId = await state.local.saveStudyLesson(
      topic: 'Titanium crystal field splitting',
      explanation: _workedExample,
      conversationId: 'readable-math-whiteboard-test',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: StudyWhiteboardScreen(state: state, lessonId: lessonId),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Study Whiteboard'), findsOneWidget);
    expect(find.textContaining('Worked example'), findsOneWidget);
    expect(find.textContaining('[Ti(H₂O)₆]³⁺'), findsOneWidget);
    expect(find.textContaining('239.4 kJ/mol'), findsOneWidget);
    expect(find.textContaining(r'\lambda'), findsNothing);
    expect(find.textContaining(r'\times'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    state.dispose();
  });
}
