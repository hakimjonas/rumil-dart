/// Hand-written recursive descent expression evaluator.
///
/// No parser combinators, no memoization, no left recursion handling.
/// Classic precedence climbing for direct comparison with Rumil's chainl1.
library;

double manualEval(String input) {
  final parser = _PrattParser(input);
  final result = parser._parseExpr();
  if (parser._pos < input.length) {
    throw FormatException('Unexpected character at ${parser._pos}');
  }
  return result;
}

class _PrattParser {
  final String _input;
  int _pos = 0;

  _PrattParser(this._input);

  void _skipWs() {
    while (_pos < _input.length && _input[_pos] == ' ') {
      _pos++;
    }
  }

  double _parseExpr() => _parseAdditive();

  double _parseAdditive() {
    var left = _parseMultiplicative();
    _skipWs();
    while (_pos < _input.length &&
        (_input[_pos] == '+' || _input[_pos] == '-')) {
      final op = _input[_pos++];
      _skipWs();
      final right = _parseMultiplicative();
      left = op == '+' ? left + right : left - right;
      _skipWs();
    }
    return left;
  }

  double _parseMultiplicative() {
    var left = _parseUnary();
    _skipWs();
    while (_pos < _input.length &&
        (_input[_pos] == '*' || _input[_pos] == '/' || _input[_pos] == '%')) {
      final op = _input[_pos++];
      _skipWs();
      final right = _parseUnary();
      left = switch (op) {
        '*' => left * right,
        '/' => left / right,
        _ => left % right,
      };
      _skipWs();
    }
    return left;
  }

  double _parseUnary() {
    _skipWs();
    if (_pos < _input.length && _input[_pos] == '-') {
      _pos++;
      return -_parsePrimary();
    }
    return _parsePrimary();
  }

  double _parsePrimary() {
    _skipWs();
    if (_pos < _input.length && _input[_pos] == '(') {
      _pos++;
      final result = _parseExpr();
      _skipWs();
      _pos++; // ')'
      return result;
    }
    return _parseNumber();
  }

  double _parseNumber() {
    _skipWs();
    final start = _pos;
    while (_pos < _input.length &&
        ((_input[_pos].compareTo('0') >= 0 &&
                _input[_pos].compareTo('9') <= 0) ||
            _input[_pos] == '.')) {
      _pos++;
    }
    return double.parse(_input.substring(start, _pos));
  }
}
