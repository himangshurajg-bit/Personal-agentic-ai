import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/circuit_guide.dart';

void main() {
  group('circuit calculations', () {
    test('solves each missing Ohm-law quantity', () {
      expect(
        solveOhmsLaw(voltage: '12', current: '2', resistance: '').value,
        6,
      );
      expect(
        solveOhmsLaw(voltage: '12', current: '', resistance: '6').value,
        2,
      );
      expect(
        solveOhmsLaw(voltage: '', current: '2', resistance: '6').value,
        12,
      );
    });

    test(
      'requires exactly two finite values and rejects invalid resistance',
      () {
        expect(
          () => solveOhmsLaw(voltage: '12', current: '', resistance: ''),
          throwsFormatException,
        );
        expect(
          () => solveOhmsLaw(voltage: '12', current: '2', resistance: '6'),
          throwsFormatException,
        );
        expect(
          () => solveOhmsLaw(voltage: '12', current: '0', resistance: ''),
          throwsFormatException,
        );
        expect(
          () => solveOhmsLaw(voltage: '12V', current: '2', resistance: ''),
          throwsFormatException,
        );
        expect(
          () => solveOhmsLaw(voltage: '', current: '2', resistance: '0'),
          throwsFormatException,
        );
      },
    );

    test('calculates loaded and unloaded voltage dividers', () {
      final unloaded = calculateVoltageDivider(
        sourceVoltage: '12',
        topResistance: '1000',
        bottomResistance: '1000',
      );
      expect(unloaded.outputVoltage, 6);
      expect(unloaded.sourceCurrent, closeTo(0.006, 1e-12));
      expect(unloaded.bottomLegCurrent, closeTo(0.006, 1e-12));
      expect(unloaded.loaded, isFalse);

      final loaded = calculateVoltageDivider(
        sourceVoltage: '12',
        topResistance: '1000',
        bottomResistance: '1000',
        loadResistance: '1000',
      );
      expect(loaded.outputVoltage, 4);
      expect(loaded.sourceCurrent, closeTo(0.008, 1e-12));
      expect(loaded.bottomLegCurrent, closeTo(0.004, 1e-12));
      expect(loaded.loaded, isTrue);
    });

    test('rejects invalid divider voltage and resistance inputs', () {
      for (final args in [
        ('', '1000', '1000', ''),
        ('12', '0', '1000', ''),
        ('12', '1000', '-1', ''),
        ('12', '1000', '1000', '0'),
        ('NaN', '1000', '1000', ''),
      ]) {
        expect(
          () => calculateVoltageDivider(
            sourceVoltage: args.$1,
            topResistance: args.$2,
            bottomResistance: args.$3,
            loadResistance: args.$4,
          ),
          throwsFormatException,
        );
      }
    });

    test('decodes a 4-band resistor and its tolerance', () {
      final decoded = decodeResistorBands('red violet orange gold');
      expect(decoded.value, 27000);
      expect(decoded.unit, 'Ω');
      expect(decoded.name, '4-band resistor (±5%)');
      expect(decodeResistorBands('brown black gold silver').value, 1);
    });

    test('decodes 5-band resistors and tolerance', () {
      final decoded = decodeResistorBands('brown black black red brown');
      expect(decoded.value, 10000);
      expect(decoded.name, '5-band resistor (±1%)');
      expect(decodeResistorBands('red violet black gold brown').value, 27);
    });

    test('rejects incomplete or invalid 4- and 5-band codes', () {
      for (final bands in [
        '',
        'red violet orange',
        'red violet orange gold white',
        'red violet orange gold silver brown',
        'blue violet orange chartreuse',
        'red violet chartreuse gold brown',
        'black red orange gold',
        'black red violet orange gold',
      ]) {
        expect(
          () => decodeResistorBands(bands),
          throwsFormatException,
          reason: bands,
        );
      }
    });

    test('rounds an LED resistor up to an E12 value and reports power', () {
      final result = calculateLedCurrentLimit(
        sourceVoltage: '9',
        ledForwardVoltage: '2',
        targetCurrentMilliAmps: '20',
      );
      expect(result.idealResistance, 350);
      expect(result.selectedResistance, 390);
      expect(result.actualCurrentMilliAmps, closeTo(17.9487179, 1e-6));
      expect(result.resistorPowerWatts, closeTo(0.125641, 1e-6));
      expect(
        result.selectedResistance,
        greaterThanOrEqualTo(result.idealResistance),
      );
      expect(result.actualCurrentMilliAmps, lessThanOrEqualTo(20));
    });

    test('rejects invalid LED calculations and extreme resistor values', () {
      for (final args in [
        ('', '2', '20'),
        ('5', '5', '20'),
        ('5', '2', '0'),
        ('NaN', '2', '20'),
        ('Infinity', '2', '20'),
        ('5', '2', '1001'),
        ('1000', '0.001', '0.0000001'),
      ]) {
        expect(
          () => calculateLedCurrentLimit(
            sourceVoltage: args.$1,
            ledForwardVoltage: args.$2,
            targetCurrentMilliAmps: args.$3,
          ),
          throwsFormatException,
          reason: args.toString(),
        );
      }
    });

    test('calculates series and parallel equivalent resistance', () {
      expect(
        equivalentResistance(values: '100, 220', parallel: false).value,
        320,
      );
      expect(
        equivalentResistance(values: '100, 100', parallel: true).value,
        closeTo(50, 1e-9),
      );
    });

    test('rejects malformed, nonpositive, and excessive resistor lists', () {
      for (final values in [
        '',
        '100',
        '100,',
        '100, nope',
        '100, 0',
        '100, -2',
      ]) {
        expect(
          () => equivalentResistance(values: values, parallel: false),
          throwsFormatException,
          reason: values,
        );
      }
      expect(
        () => equivalentResistance(
          values: List.filled(21, '10').join(','),
          parallel: true,
        ),
        throwsFormatException,
      );
    });
  });

  testWidgets('screen shows a local Ohm-law calculation', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: CircuitGuideScreen()));
    expect(
      find.textContaining('does not inspect or control hardware'),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const ValueKey('circuit-voltage')), '12');
    await tester.enterText(find.byKey(const ValueKey('circuit-current')), '2');
    await tester.ensureVisible(
      find.byKey(const ValueKey('calculate-ohms-law')),
    );
    await tester.tap(find.byKey(const ValueKey('calculate-ohms-law')));
    await tester.pumpAndSettle();
    expect(find.text('Resistance: 6 Ω'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('screen calculates a loaded voltage divider locally', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: CircuitGuideScreen()));
    await tester.ensureVisible(find.byKey(const ValueKey('divider-source')));
    await tester.enterText(find.byKey(const ValueKey('divider-source')), '12');
    await tester.enterText(find.byKey(const ValueKey('divider-top')), '1000');
    await tester.enterText(
      find.byKey(const ValueKey('divider-bottom')),
      '1000',
    );
    await tester.enterText(find.byKey(const ValueKey('divider-load')), '1000');
    await tester.ensureVisible(
      find.byKey(const ValueKey('calculate-voltage-divider')),
    );
    await tester.tap(find.byKey(const ValueKey('calculate-voltage-divider')));
    await tester.pumpAndSettle();
    expect(find.text('Loaded divider output: 4 V'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('screen estimates a current-limiting LED resistor', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: CircuitGuideScreen()));
    await tester.ensureVisible(find.byKey(const ValueKey('led-source')));
    await tester.enterText(find.byKey(const ValueKey('led-source')), '9');
    await tester.enterText(
      find.byKey(const ValueKey('led-forward-voltage')),
      '2',
    );
    await tester.enterText(
      find.byKey(const ValueKey('led-target-current')),
      '20',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('calculate-led-resistor')),
    );
    await tester.tap(find.byKey(const ValueKey('calculate-led-resistor')));
    await tester.pumpAndSettle();
    expect(find.text('LED series resistor (E12): 390 Ω'), findsOneWidget);
    expect(find.textContaining('Current: 17.95 mA'), findsOneWidget);
    expect(
      find.textContaining('Resistor dissipation: 0.1256 W'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('screen decodes resistor bands locally', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: CircuitGuideScreen()));
    await tester.ensureVisible(
      find.byKey(const ValueKey('resistor-color-bands')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('resistor-color-bands')),
      'red violet orange gold',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('decode-resistor-bands')),
    );
    await tester.tap(find.byKey(const ValueKey('decode-resistor-bands')));
    await tester.pumpAndSettle();
    expect(find.text('4-band resistor (±5%): 27000 Ω'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid inputs show a local validation message only', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: CircuitGuideScreen()));
    await tester.enterText(find.byKey(const ValueKey('circuit-voltage')), '10');
    await tester.ensureVisible(
      find.byKey(const ValueKey('calculate-ohms-law')),
    );
    await tester.tap(find.byKey(const ValueKey('calculate-ohms-law')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('circuit-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('circuit-result')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
