/// Converts common LaTeX math markup into readable Unicode/plain text before
/// passing mixed prose to the Markdown renderer. This deliberately does not
/// evaluate expressions: operators, signs, units, and significant digits stay
/// visible exactly as supplied.
class ReadableMath {
  ReadableMath._();

  static String formatMarkdown(String source) {
    final output = StringBuffer();
    var index = 0;
    var inFence = false;

    while (index < source.length) {
      if (_startsWith(source, index, '```')) {
        inFence = !inFence;
        output.write('```');
        index += 3;
        continue;
      }
      if (inFence) {
        output.write(source[index++]);
        continue;
      }

      // Inline code is literal, so leave any TeX-looking examples untouched.
      if (source[index] == '`') {
        final runEnd = _runEnd(source, index, '`');
        final ticks = source.substring(index, runEnd);
        final close = source.indexOf(ticks, runEnd);
        if (close >= 0) {
          output.write(source.substring(index, close + ticks.length));
          index = close + ticks.length;
          continue;
        }
      }

      final delimiter = _openingDelimiter(source, index);
      if (delimiter == null) {
        output.write(source[index++]);
        continue;
      }

      final close = _findClosing(source, index + delimiter.length, delimiter);
      if (close < 0) {
        // A lone dollar is usually currency, not an opening math delimiter.
        // Do not let it capture a later equation on another line.
        if (delimiter == r'$') {
          output.write(source[index++]);
          continue;
        }
        output.write(source.substring(index));
        break;
      }
      final expression = source.substring(index + delimiter.length, close);
      if (_looksLikeMath(expression)) {
        output.write(_TexReader(expression).parse());
      } else {
        output.write(source.substring(index, close + delimiter.length));
      }
      index = close + delimiter.length;
    }
    return output.toString();
  }

  static bool _startsWith(String source, int offset, String value) =>
      source.startsWith(value, offset);

  static int _runEnd(String source, int offset, String char) {
    var end = offset;
    while (end < source.length && source[end] == char) {
      end++;
    }
    return end;
  }

  static String? _openingDelimiter(String source, int index) {
    if (source.startsWith(r'\(', index)) return r'\(';
    if (source.startsWith(r'\[', index)) return r'\[';
    if (source.startsWith(r'$$', index)) return r'$$';
    if (source[index] == r'$' && (index == 0 || source[index - 1] != r'\')) {
      return r'$';
    }
    return null;
  }

  static int _findClosing(String source, int start, String delimiter) {
    var cursor = start;
    while (cursor < source.length) {
      final found = source.indexOf(delimiter, cursor);
      if (found < 0) return -1;
      var backslashes = 0;
      for (var i = found - 1; i >= 0 && source[i] == r'\'; i--) {
        backslashes++;
      }
      if (delimiter == r'$' && source.substring(start, found).contains('\n')) {
        return -1;
      }
      if (backslashes.isEven) return found;
      cursor = found + delimiter.length;
    }
    return -1;
  }

  static bool _looksLikeMath(String expression) =>
      expression.contains(r'\') ||
      expression.contains('_') ||
      expression.contains('^');
}

class _TexReader {
  _TexReader(this.source);

  final String source;
  var index = 0;

  String parse() => _readUntil();

  String _readUntil({String? stopAt}) {
    final output = StringBuffer();
    while (index < source.length) {
      final char = source[index];
      if (stopAt != null && char == stopAt) {
        index++;
        break;
      }
      if (char == '\\') {
        index++;
        if (index < source.length && source[index] == '\\') {
          index++;
          output.write('\n');
        } else if (index < source.length && ',;:! '.contains(source[index])) {
          output.write(' ');
          index++;
        } else if (index < source.length &&
            (source[index] == '%' ||
                source[index] == '_' ||
                source[index] == '{' ||
                source[index] == '}' ||
                source[index] == '&' ||
                source[index] == r'$')) {
          output.write(source[index++]);
        } else if (index < source.length && _isLetter(source[index])) {
          final nameStart = index;
          while (index < source.length && _isLetter(source[index])) {
            index++;
          }
          output.write(_command(source.substring(nameStart, index)));
        }
        continue;
      }
      if (char == '{') {
        index++;
        output.write(_readUntil(stopAt: '}'));
        continue;
      }
      if (char == '}') {
        index++;
        continue;
      }
      if (char == '^' || char == '_') {
        index++;
        _skipSpaces();
        final argument = _readArgument();
        output.write(_script(argument, superscript: char == '^'));
        continue;
      }
      output.write(char);
      index++;
    }
    return output.toString();
  }

  String _command(String name) {
    switch (name) {
      case 'text':
      case 'mathrm':
      case 'mathbf':
      case 'mathit':
      case 'operatorname':
        return _readArgument();
      case 'frac':
      case 'dfrac':
      case 'tfrac':
        final numerator = _readArgument().trim();
        final denominator = _readArgument().trim();
        return '($numerator)/($denominator)';
      case 'sqrt':
        return '√(${_readArgument().trim()})';
      case 'left':
      case 'right':
      case 'displaystyle':
      case 'textstyle':
        return '';
      case 'times':
        return '×';
      case 'cdot':
        return '·';
      case 'pm':
        return '±';
      case 'mp':
        return '∓';
      case 'approx':
        return '≈';
      case 'neq':
      case 'ne':
        return '≠';
      case 'le':
      case 'leq':
        return '≤';
      case 'ge':
      case 'geq':
        return '≥';
      case 'rightarrow':
      case 'to':
        return '→';
      case 'degree':
        return '°';
      case 'infty':
        return '∞';
      case 'Delta':
        return 'Δ';
      case 'delta':
        return 'δ';
      case 'lambda':
        return 'λ';
      case 'theta':
        return 'θ';
      case 'Theta':
        return 'Θ';
      case 'alpha':
        return 'α';
      case 'beta':
        return 'β';
      case 'gamma':
        return 'γ';
      case 'Gamma':
        return 'Γ';
      case 'mu':
        return 'μ';
      case 'pi':
        return 'π';
      case 'rho':
        return 'ρ';
      case 'sigma':
        return 'σ';
      case 'Sigma':
        return 'Σ';
      case 'omega':
        return 'ω';
      case 'Omega':
        return 'Ω';
      case 'phi':
        return 'φ';
      case 'Phi':
        return 'Φ';
      case 'chi':
        return 'χ';
      case 'psi':
        return 'ψ';
      case 'epsilon':
        return 'ε';
      case 'varepsilon':
        return 'ϵ';
      case 'ldots':
      case 'cdots':
        return '…';
      case 'quad':
      case 'qquad':
        return '  ';
      case 'overline':
      case 'bar':
        return '${_readArgument().trim()}̅';
      case 'vec':
        return '${_readArgument().trim()}⃗';
      default:
        // Keep an unfamiliar command's readable name rather than leaking raw
        // TeX syntax into the user's prose.
        return name;
    }
  }

  String _readArgument() {
    _skipSpaces();
    if (index >= source.length) return '';
    if (source[index] == '{') {
      index++;
      return _readUntil(stopAt: '}');
    }
    if (source[index] == r'\' && index + 1 < source.length) {
      index++;
      if (_isLetter(source[index])) {
        final start = index;
        while (index < source.length && _isLetter(source[index])) {
          index++;
        }
        return _command(source.substring(start, index));
      }
    }
    final value = source[index++];
    return value;
  }

  void _skipSpaces() {
    while (index < source.length && source[index].trim().isEmpty) {
      index++;
    }
  }

  static bool _isLetter(String value) => RegExp(r'[A-Za-z]').hasMatch(value);

  static String _script(String value, {required bool superscript}) {
    final substitutions = superscript ? _superscripts : _subscripts;
    final converted = StringBuffer();
    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      final replacement = substitutions[char];
      if (replacement == null) {
        return '${superscript ? '^' : '_'}(${value.trim()})';
      }
      converted.write(replacement);
    }
    return converted.toString();
  }

  static const _subscripts = <String, String>{
    '0': '₀',
    '1': '₁',
    '2': '₂',
    '3': '₃',
    '4': '₄',
    '5': '₅',
    '6': '₆',
    '7': '₇',
    '8': '₈',
    '9': '₉',
    '+': '₊',
    '-': '₋',
    '=': '₌',
    '(': '₍',
    ')': '₎',
    'a': 'ₐ',
    'e': 'ₑ',
    'h': 'ₕ',
    'i': 'ᵢ',
    'j': 'ⱼ',
    'k': 'ₖ',
    'l': 'ₗ',
    'm': 'ₘ',
    'n': 'ₙ',
    'o': 'ₒ',
    'p': 'ₚ',
    'r': 'ᵣ',
    's': 'ₛ',
    't': 'ₜ',
    'u': 'ᵤ',
    'v': 'ᵥ',
    'x': 'ₓ',
  };

  static const _superscripts = <String, String>{
    '0': '⁰',
    '1': '¹',
    '2': '²',
    '3': '³',
    '4': '⁴',
    '5': '⁵',
    '6': '⁶',
    '7': '⁷',
    '8': '⁸',
    '9': '⁹',
    '+': '⁺',
    '-': '⁻',
    '=': '⁼',
    '(': '⁽',
    ')': '⁾',
    'n': 'ⁿ',
    'i': 'ⁱ',
  };
}
