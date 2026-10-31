import 'package:flutter/material.dart';

import 'main.dart' show Glass, Shell;

class CircuitCalculation {
  const CircuitCalculation({
    required this.name,
    required this.value,
    required this.unit,
  });

  final String name;
  final double value;
  final String unit;

  String get formattedValue {
    if (value == 0) return '0';
    if (value >= 1000000 || value < 0.001) {
      return value.toStringAsExponential(3);
    }
    final rounded = double.parse(value.toStringAsPrecision(6)).toString();
    return rounded.endsWith('.0')
        ? rounded.substring(0, rounded.length - 2)
        : rounded;
  }
}

/// Solves exactly one missing value from V = I × R; this is educational,
/// calculation-only logic and never controls a physical circuit.
CircuitCalculation solveOhmsLaw({
  required String voltage,
  required String current,
  required String resistance,
}) {
  final raw = [voltage.trim(), current.trim(), resistance.trim()];
  if (raw.where((value) => value.isNotEmpty).length != 2) {
    throw const FormatException(
      'Enter exactly two values to calculate the third.',
    );
  }
  final parsed = raw
      .map((value) => value.isEmpty ? null : double.tryParse(value))
      .toList(growable: false);
  if (raw.asMap().entries.any(
    (entry) => entry.value.isNotEmpty && parsed[entry.key] == null,
  )) {
    throw const FormatException('Use numbers only, such as 5 or 0.25.');
  }
  final v = parsed[0];
  final i = parsed[1];
  final r = parsed[2];
  if ((v != null && (v < 0 || !v.isFinite)) ||
      (i != null && (i < 0 || !i.isFinite)) ||
      (r != null && (r <= 0 || !r.isFinite))) {
    throw const FormatException(
      'Voltage and current must be zero or greater; resistance must be greater than zero.',
    );
  }
  late final String name;
  late final double result;
  late final String unit;
  if (v == null) {
    name = 'Voltage';
    result = i! * r!;
    unit = 'V';
  } else if (i == null) {
    name = 'Current';
    result = v / r!;
    unit = 'A';
  } else {
    if (i == 0) {
      throw const FormatException(
        'Resistance cannot be determined from zero current; enter voltage and resistance instead.',
      );
    }
    name = 'Resistance';
    result = v / i;
    unit = 'Ω';
  }
  if (!result.isFinite || result > 1e12) {
    throw const FormatException('The result is outside the supported range.');
  }
  return CircuitCalculation(name: name, value: result, unit: unit);
}

class VoltageDividerCalculation {
  const VoltageDividerCalculation({
    required this.outputVoltage,
    required this.sourceCurrent,
    required this.bottomLegCurrent,
    required this.loaded,
  });

  final double outputVoltage;
  final double sourceCurrent;
  final double bottomLegCurrent;
  final bool loaded;
}

/// Calculates an educational two-resistor divider, optionally with a load.
/// It is a calculation only and never controls or validates real hardware.
VoltageDividerCalculation calculateVoltageDivider({
  required String sourceVoltage,
  required String topResistance,
  required String bottomResistance,
  String loadResistance = '',
}) {
  double parse(String input, String label, {bool allowZero = false}) {
    final value = double.tryParse(input.trim());
    if (value == null ||
        !value.isFinite ||
        (allowZero ? value < 0 : value <= 0) ||
        value > 1e12) {
      throw FormatException(
        '$label must be a ${allowZero ? 'nonnegative' : 'positive'} number up to 1 trillion.',
      );
    }
    return value;
  }

  final input = parse(sourceVoltage, 'Source voltage', allowZero: true);
  final top = parse(topResistance, 'Top resistance');
  final bottom = parse(bottomResistance, 'Bottom resistance');
  final loadText = loadResistance.trim();
  final load = loadText.isEmpty ? null : parse(loadText, 'Load resistance');
  final effectiveBottom = load == null ? bottom : 1 / (1 / bottom + 1 / load);
  final totalResistance = top + effectiveBottom;
  final output = input * effectiveBottom / totalResistance;
  final sourceCurrent = input / totalResistance;
  final bottomCurrent = output / bottom;
  if (!output.isFinite || !sourceCurrent.isFinite || !bottomCurrent.isFinite) {
    throw const FormatException('The result is outside the supported range.');
  }
  return VoltageDividerCalculation(
    outputVoltage: output,
    sourceCurrent: sourceCurrent,
    bottomLegCurrent: bottomCurrent,
    loaded: load != null,
  );
}

/// Decodes a common 4- or 5-band resistor color code, e.g. "red violet orange gold".
/// This is a learning aid; confirm component markings with a meter before use.
CircuitCalculation decodeResistorBands(String bands) {
  const digits = <String, int>{
    'black': 0,
    'brown': 1,
    'red': 2,
    'orange': 3,
    'yellow': 4,
    'green': 5,
    'blue': 6,
    'violet': 7,
    'purple': 7,
    'gray': 8,
    'grey': 8,
    'white': 9,
  };
  const multipliers = <String, double>{
    'pink': 0.001,
    'silver': 0.01,
    'gold': 0.1,
    'black': 1,
    'brown': 10,
    'red': 100,
    'orange': 1000,
    'yellow': 10000,
    'green': 100000,
    'blue': 1000000,
    'violet': 10000000,
    'gray': 100000000,
    'grey': 100000000,
    'white': 1000000000,
  };
  const tolerances = <String, double>{
    'brown': 1,
    'red': 2,
    'green': 0.5,
    'blue': 0.25,
    'violet': 0.1,
    'gray': 0.05,
    'grey': 0.05,
    'gold': 5,
    'silver': 10,
  };
  final colors = bands
      .toLowerCase()
      .trim()
      .split(RegExp(r'\s+'))
      .where((color) => color.isNotEmpty)
      .toList(growable: false);
  if (colors.length != 4 && colors.length != 5) {
    throw const FormatException(
      'Enter four or five band colors, such as red violet orange gold.',
    );
  }
  final digitCount = colors.length == 5 ? 3 : 2;
  final significantDigits = <int>[];
  for (var i = 0; i < digitCount; i++) {
    final digit = digits[colors[i]];
    if (digit == null) {
      throw const FormatException(
        'Use valid colors: black, brown, red, orange, yellow, green, blue, violet, gray, white, gold, or silver.',
      );
    }
    significantDigits.add(digit);
  }
  final multiplier = multipliers[colors[digitCount]];
  final tolerance = tolerances[colors[digitCount + 1]];
  if (multiplier == null || tolerance == null) {
    throw const FormatException(
      'Use valid colors: black, brown, red, orange, yellow, green, blue, violet, gray, white, gold, or silver.',
    );
  }
  if (significantDigits.first == 0) {
    throw const FormatException('The first band cannot be black.');
  }
  final significantValue = significantDigits.fold<int>(
    0,
    (value, digit) => value * 10 + digit,
  );
  final value = significantValue * multiplier;
  if (!value.isFinite || value <= 0 || value > 1e12) {
    throw const FormatException(
      'The decoded resistance is outside the supported range.',
    );
  }
  final toleranceText = tolerance.toString().replaceFirst(RegExp(r'\.0$'), '');
  return CircuitCalculation(
    name: '${colors.length}-band resistor (±$toleranceText%)',
    value: value,
    unit: 'Ω',
  );
}

class LedCurrentLimitCalculation {
  const LedCurrentLimitCalculation({
    required this.idealResistance,
    required this.selectedResistance,
    required this.actualCurrentMilliAmps,
    required this.resistorPowerWatts,
  });

  final double idealResistance;
  final double selectedResistance;
  final double actualCurrentMilliAmps;
  final double resistorPowerWatts;
}

/// Estimates a current-limiting resistor and rounds up to the next E12 value.
/// Educational only: component ratings, tolerances, thermal conditions, and
/// circuit suitability must be checked independently before building anything.
LedCurrentLimitCalculation calculateLedCurrentLimit({
  required String sourceVoltage,
  required String ledForwardVoltage,
  required String targetCurrentMilliAmps,
}) {
  double parse(String text, String label, {double max = 1000}) {
    final value = double.tryParse(text.trim());
    if (value == null || !value.isFinite || value <= 0 || value > max) {
      throw FormatException('$label must be greater than zero and at most $max.');
    }
    return value;
  }

  final source = parse(sourceVoltage, 'Source voltage');
  final forward = parse(ledForwardVoltage, 'LED forward voltage');
  final targetMilliAmps = parse(targetCurrentMilliAmps, 'Target current');
  if (source <= forward) {
    throw const FormatException(
      'Source voltage must be greater than the LED forward voltage.',
    );
  }
  final drop = source - forward;
  final ideal = drop / (targetMilliAmps / 1000);
  if (!ideal.isFinite || ideal <= 0 || ideal > 1e12) {
    throw const FormatException('The calculated resistance is outside the supported range.');
  }
  const e12 = <double>[1, 1.2, 1.5, 1.8, 2.2, 2.7, 3.3, 3.9, 4.7, 5.6, 6.8, 8.2];
  double? selected;
  for (var decade = -1; decade <= 12 && selected == null; decade++) {
    final scale = decade >= 0
        ? _powerOfTen(decade)
        : 1 / _powerOfTen(-decade);
    for (final base in e12) {
      final candidate = base * scale;
      if (candidate >= ideal) {
        selected = candidate;
        break;
      }
    }
  }
  if (selected == null || !selected.isFinite) {
    throw const FormatException('No standard resistor is available in the supported range.');
  }
  final actualCurrent = drop / selected * 1000;
  final power = drop * drop / selected;
  if (!actualCurrent.isFinite || !power.isFinite) {
    throw const FormatException('The result is outside the supported range.');
  }
  return LedCurrentLimitCalculation(
    idealResistance: ideal,
    selectedResistance: selected,
    actualCurrentMilliAmps: actualCurrent,
    resistorPowerWatts: power,
  );
}

double _powerOfTen(int exponent) {
  var result = 1.0;
  for (var i = 0; i < exponent; i++) {
    result *= 10;
  }
  return result;
}

/// Computes an equivalent resistance from 2–20 positive resistor values.
CircuitCalculation equivalentResistance({
  required String values,
  required bool parallel,
}) {
  final tokens = values.split(',').map((part) => part.trim()).toList();
  if (tokens.length < 2 ||
      tokens.length > 20 ||
      tokens.any((part) => part.isEmpty)) {
    throw const FormatException(
      'Enter 2–20 resistor values separated by commas.',
    );
  }
  final resistors = tokens.map(double.tryParse).toList(growable: false);
  if (resistors.any(
    (value) => value == null || !value.isFinite || value <= 0 || value > 1e12,
  )) {
    throw const FormatException(
      'Each resistance must be a positive number up to 1 trillion Ω.',
    );
  }
  final numbers = resistors.cast<double>();
  final result = parallel
      ? 1 / numbers.fold<double>(0, (sum, value) => sum + 1 / value)
      : numbers.fold<double>(0, (sum, value) => sum + value);
  if (!result.isFinite || result <= 0) {
    throw const FormatException('The result is outside the supported range.');
  }
  return CircuitCalculation(
    name: parallel
        ? 'Parallel equivalent resistance'
        : 'Series equivalent resistance',
    value: result,
    unit: 'Ω',
  );
}

class CircuitGuideScreen extends StatefulWidget {
  const CircuitGuideScreen({super.key});

  @override
  State<CircuitGuideScreen> createState() => _CircuitGuideScreenState();
}

class _CircuitGuideScreenState extends State<CircuitGuideScreen> {
  final _voltage = TextEditingController();
  final _current = TextEditingController();
  final _resistance = TextEditingController();
  final _resistors = TextEditingController();
  final _bands = TextEditingController();
  final _dividerVoltage = TextEditingController();
  final _dividerTop = TextEditingController();
  final _dividerBottom = TextEditingController();
  final _dividerLoad = TextEditingController();
  final _ledSource = TextEditingController();
  final _ledForward = TextEditingController();
  final _ledCurrent = TextEditingController();
  bool _parallel = false;
  CircuitCalculation? _result;
  String _resultDetails = '';
  String _error = '';

  @override
  void dispose() {
    _voltage.dispose();
    _current.dispose();
    _resistance.dispose();
    _resistors.dispose();
    _bands.dispose();
    _dividerVoltage.dispose();
    _dividerTop.dispose();
    _dividerBottom.dispose();
    _dividerLoad.dispose();
    _ledSource.dispose();
    _ledForward.dispose();
    _ledCurrent.dispose();
    super.dispose();
  }

  void _calculateOhms() {
    try {
      final result = solveOhmsLaw(
        voltage: _voltage.text,
        current: _current.text,
        resistance: _resistance.text,
      );
      setState(() {
        _result = result;
        _resultDetails = '';
        _error = '';
      });
    } on FormatException catch (error) {
      setState(() {
        _result = null;
        _resultDetails = '';
        _error = error.message;
      });
    }
  }

  void _calculateEquivalent() {
    try {
      final result = equivalentResistance(
        values: _resistors.text,
        parallel: _parallel,
      );
      setState(() {
        _result = result;
        _resultDetails = '';
        _error = '';
      });
    } on FormatException catch (error) {
      setState(() {
        _result = null;
        _resultDetails = '';
        _error = error.message;
      });
    }
  }

  void _calculateDivider() {
    try {
      final divider = calculateVoltageDivider(
        sourceVoltage: _dividerVoltage.text,
        topResistance: _dividerTop.text,
        bottomResistance: _dividerBottom.text,
        loadResistance: _dividerLoad.text,
      );
      final result = CircuitCalculation(
        name: divider.loaded
            ? 'Loaded divider output'
            : 'Voltage divider output',
        value: divider.outputVoltage,
        unit: 'V',
      );
      setState(() {
        _result = result;
        _resultDetails = '';
        _error = '';
      });
    } on FormatException catch (error) {
      setState(() {
        _result = null;
        _resultDetails = '';
        _error = error.message;
      });
    }
  }

  void _calculateLedResistor() {
    try {
      final calculation = calculateLedCurrentLimit(
        sourceVoltage: _ledSource.text,
        ledForwardVoltage: _ledForward.text,
        targetCurrentMilliAmps: _ledCurrent.text,
      );
      setState(() {
        _result = CircuitCalculation(
          name: 'LED series resistor (E12)',
          value: calculation.selectedResistance,
          unit: 'Ω',
        );
        _resultDetails =
            'Ideal: ${calculation.idealResistance.toStringAsPrecision(5)} Ω · '
            'Current: ${calculation.actualCurrentMilliAmps.toStringAsPrecision(4)} mA · '
            'Resistor dissipation: ${calculation.resistorPowerWatts.toStringAsPrecision(4)} W';
        _error = '';
      });
    } on FormatException catch (error) {
      setState(() {
        _result = null;
        _resultDetails = '';
        _error = error.message;
      });
    }
  }

  void _decodeBands() {
    try {
      final result = decodeResistorBands(_bands.text);
      setState(() {
        _result = result;
        _resultDetails = '';
        _error = '';
      });
    } on FormatException catch (error) {
      setState(() {
        _result = null;
        _resultDetails = '';
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Shell(
    title: 'Circuit guide',
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 118),
      children: [
        Text(
          'Quick circuit calculations',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Solve basic Ohm’s law or combine resistors. This is an educational calculator only; it does not inspect or control hardware.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 14),
        Glass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Ohm’s law · V = I × R',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              _numberField(_voltage, 'Voltage (V)', 'circuit-voltage'),
              _numberField(_current, 'Current (A)', 'circuit-current'),
              _numberField(_resistance, 'Resistance (Ω)', 'circuit-resistance'),
              FilledButton.tonal(
                key: const ValueKey('calculate-ohms-law'),
                onPressed: _calculateOhms,
                child: const Text('Calculate missing value'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Glass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Equivalent resistance',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('circuit-resistor-values'),
                controller: _resistors,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Resistor values in Ω',
                  hintText: 'e.g. 100, 220, 330',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                key: const ValueKey('circuit-connection-type'),
                segments: const [
                  ButtonSegment(value: false, label: Text('Series')),
                  ButtonSegment(value: true, label: Text('Parallel')),
                ],
                selected: {_parallel},
                onSelectionChanged: (selection) => setState(() {
                  _parallel = selection.single;
                  _result = null;
                  _error = '';
                }),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                key: const ValueKey('calculate-equivalent-resistance'),
                onPressed: _calculateEquivalent,
                child: const Text('Calculate equivalent'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Glass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Voltage divider',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              _numberField(
                _dividerVoltage,
                'Source voltage (V)',
                'divider-source',
              ),
              _numberField(_dividerTop, 'Top resistor R₁ (Ω)', 'divider-top'),
              _numberField(
                _dividerBottom,
                'Bottom resistor R₂ (Ω)',
                'divider-bottom',
              ),
              _numberField(_dividerLoad, 'Optional load (Ω)', 'divider-load'),
              const Text(
                'Leave load empty for an unloaded divider. A connected load reduces the output voltage.',
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                key: const ValueKey('calculate-voltage-divider'),
                onPressed: _calculateDivider,
                child: const Text('Calculate output voltage'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Glass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'LED series resistor (E12 estimate)',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              _numberField(_ledSource, 'Supply voltage (V)', 'led-source'),
              _numberField(_ledForward, 'LED forward voltage (V)', 'led-forward-voltage'),
              _numberField(_ledCurrent, 'Target current (mA)', 'led-target-current'),
              const Text(
                'Rounds up to a common E12 resistor. Check the LED and resistor datasheets; this is not a hardware safety check.',
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                key: const ValueKey('calculate-led-resistor'),
                onPressed: _calculateLedResistor,
                child: const Text('Estimate resistor'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Glass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Read a 4- or 5-band resistor',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('resistor-color-bands'),
                controller: _bands,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Four or five bands, left to right',
                  hintText: 'e.g. red violet orange gold or brown black black red brown',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                key: const ValueKey('decode-resistor-bands'),
                onPressed: _decodeBands,
                child: const Text('Decode resistor'),
              ),
            ],
          ),
        ),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 10),
          Semantics(
            liveRegion: true,
            child: Text(
              _error,
              key: const ValueKey('circuit-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
        if (_result != null) ...[
          const SizedBox(height: 10),
          Semantics(
            liveRegion: true,
            child: Glass(
              key: const ValueKey('circuit-result'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_result!.name}: ${_result!.formattedValue} ${_result!.unit}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (_resultDetails.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(_resultDetails),
                  ],
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        const Glass(
          child: Text(
            'Safety: use this only for learning and low-voltage calculations. It is not a wiring design or safety check. Don’t use it to work on mains electricity, batteries, or live equipment.',
          ),
        ),
      ],
    ),
  );

  Widget _numberField(
    TextEditingController controller,
    String label,
    String key,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextField(
      key: ValueKey(key),
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );
}
