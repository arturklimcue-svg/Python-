// Pure-Dart interpreter for the Python subset taught in the course.
// No Flutter / dart:ui dependencies so it can run tests on any platform.
// ignore_for_file: non_constant_identifier_names, prefer_final_locals, library_private_types_in_public_api
import 'dart:convert' as convert;
import 'dart:isolate';
import 'dart:math' as math;

class PyError implements Exception {
  final String message;
  PyError(this.message);
  @override
  String toString() => message;
}

class PyRunResult {
  final bool ok;
  final String stdout;
  final String error;

  /// Сколько раз программа вызвала `input()`, не получив готовой строки
  /// (данные во `stdin` закончились). Больше нуля — программа ждёт ввод.
  final int inputsMissing;

  const PyRunResult(this.ok, this.stdout, this.error, {this.inputsMissing = 0});
}

/// Runs a Python-subset program synchronously.
///
/// [seed] задаёт зерно генератора `random` (для воспроизводимых прогонов).
/// Если не указано, зерно берётся случайным — как в настоящем Python.
PyRunResult runPython(String code, {String stdin = '', int? seed}) {
  final interp = _Interp(stdin, seed);
  try {
    final tokens = _Lexer(code).tokenize();
    final program = _Parser(tokens).parseProgram();
    interp.execProgram(program);
    return PyRunResult(true, interp.out.toString(), '',
        inputsMissing: interp.inputsMissing);
  } on PyError catch (e) {
    return PyRunResult(false, interp.out.toString(), e.message,
        inputsMissing: interp.inputsMissing);
  } catch (e) {
    return PyRunResult(false, interp.out.toString(), e.toString(),
        inputsMissing: interp.inputsMissing);
  }
}

/// Runs a Python-subset program on a background isolate so the UI stays
/// responsive even for long or infinite loops. Result is sendable.
Future<PyRunResult> runPythonAsync(String code,
    {String stdin = '', int? seed}) {
  return Isolate.run(() => runPython(code, stdin: stdin, seed: seed));
}

// ---------------------------------------------------------------------------
// Values
// ---------------------------------------------------------------------------

class PyNone {
  const PyNone._();
}

const pyNone = PyNone._();

class PyList {
  final List<dynamic> items;
  PyList([List<dynamic>? items]) : items = items ?? [];
}

class PyTuple {
  final List<dynamic> items;
  PyTuple(this.items);
}

class PyDict {
  final List<List<dynamic>> entries; // [key, value] preserving order
  PyDict([List<List<dynamic>>? entries]) : entries = entries ?? [];
}

class PyRange {
  final int start, stop, step;
  PyRange(this.start, this.stop, this.step);
  List<int> toList() {
    final out = <int>[];
    if (step > 0) {
      for (var i = start; i < stop; i += step) {
        out.add(i);
      }
    } else {
      for (var i = start; i > stop; i += step) {
        out.add(i);
      }
    }
    return out;
  }
}

class PySet {
  final List<dynamic> items;
  PySet([List<dynamic>? items]) : items = items ?? [];
}

class PyResponse {
  final int statusCode;
  final String reason;
  final dynamic payload; // PyDict / PyList
  final PyDict headers;
  final String url;
  PyResponse(this.statusCode, this.reason, this.payload, this.headers, this.url);
}

class PyFunction {
  final String name;
  final List<String> params;
  final List<dynamic> defaults; // raw default values (evaluated)
  final List<Stmt> body;
  final Expr? exprBody;
  final _Scope closure;
  final int defaultCount;
  String? vararg;
  String? kwarg;
  PyClass? owner;
  bool isStatic = false;
  bool isProperty = false;
  PyFunction({
    required this.name,
    required this.params,
    required this.defaults,
    required this.body,
    required this.closure,
    this.exprBody,
    required this.defaultCount,
  });
}

class PyBuiltin {
  final String name;
  final dynamic Function(List<dynamic> args, Map<String, dynamic> kwargs) fn;
  PyBuiltin(this.name, this.fn);
}

class PyBoundMethod {
  final dynamic target;
  final dynamic method; // PyFunction or PyBuiltin
  PyBoundMethod(this.target, this.method);
}

class PyBoundBuiltin {
  final dynamic target;
  final String name;
  final dynamic Function(dynamic target, List<dynamic> args,
      Map<String, dynamic> kwargs) fn;
  PyBoundBuiltin(this.target, this.name, this.fn);
}

class PyClass {
  final String name;
  final List<PyClass> bases;
  final Map<String, dynamic> classAttrs = {};
  final Map<String, PyFunction> methods = {};
  PyClass(this.name, this.bases);
}

class PyInstance {
  final PyClass cls;
  final Map<String, dynamic> attrs = {};
  PyInstance(this.cls);
}

class PySuper {
  final PyInstance instance;
  final PyClass startClass;
  PySuper(this.instance, this.startClass);
}

class PyNamespace {
  final String name;
  final Map<String, dynamic> attrs;
  PyNamespace(this.name, this.attrs);
}

// ---------------------------------------------------------------------------
// Tokens
// ---------------------------------------------------------------------------

enum _Tk { num, str, name, op, newline, indent, dedent, eof }

class _Tok {
  final _Tk t;
  final String v;
  final dynamic lit;
  final bool isF;
  final int line;
  _Tok(this.t, this.v, {this.lit, this.isF = false, this.line = 0});
  bool isOp(String s) => t == _Tk.op && v == s;
  bool isName(String s) => t == _Tk.name && v == s;
  @override
  String toString() => '${t.name}($v)';
}

// ---------------------------------------------------------------------------
// Lexer
// ---------------------------------------------------------------------------

class _Lexer {
  final String src;
  int pos = 0;
  int line = 1;
  bool atLineStart = true;
  bool continued = false;
  int bracketDepth = 0;
  final List<int> indents = [0];
  final List<_Tok> tokens = [];

  _Lexer(this.src);

  bool _isLetter(int c) =>
      (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c > 127;
  bool _isDigit(int c) => c >= 48 && c <= 57;
  bool _isAlnum(int c) => _isLetter(c) || _isDigit(c);

  List<_Tok> tokenize() {
    final n = src.length;
    while (pos < n) {
      if (atLineStart && bracketDepth == 0) {
        var i = pos;
        var indent = 0;
        while (i < n && (src[i] == ' ' || src[i] == '\t')) {
          indent += src[i] == '\t' ? 8 : 1;
          i++;
        }
        if (i >= n) {
          pos = i;
          break;
        }
        if (src[i] == '\n') {
          pos = i + 1;
          line++;
          continue;
        }
        if (src[i] == '\r') {
          pos = i + 1;
          continue;
        }
        if (src[i] == '#') {
          while (i < n && src[i] != '\n') {
            i++;
          }
          pos = i;
          continue;
        }
        if (!continued) _handleIndent(indent);
        continued = false;
        pos = i;
        atLineStart = false;
        continue;
      }
      final c = src.codeUnitAt(pos);
      if (c == 10) {
        pos++;
        line++;
        if (bracketDepth > 0) continue;
        _emit(_Tok(_Tk.newline, '\n', line: line));
        atLineStart = true;
        continue;
      }
      if (c == 13 || c == 32 || c == 9) {
        pos++;
        continue;
      }
      if (c == 92 && pos + 1 < n && src[pos + 1] == '\n') {
        pos += 2;
        line++;
        continued = true;
        continue;
      }
      if (c == 35) {
        while (pos < n && src[pos] != '\n') {
          pos++;
        }
        continue;
      }
      if (_isLetter(c)) {
        final start = pos;
        pos++;
        while (pos < n && _isAlnum(src.codeUnitAt(pos))) {
          pos++;
        }
        final word = src.substring(start, pos);
        if (pos < n &&
            (src[pos] == '"' || src[pos] == "'") &&
            const {'f', 'r', 'fr', 'rf'}.contains(word.toLowerCase())) {
          _emit(_readString(word));
          continue;
        }
        _emit(_Tok(_Tk.name, word, line: line));
        continue;
      }
      if (c == 34 || c == 39) {
        _emit(_readString(''));
        continue;
      }
      if (_isDigit(c) || (c == 46 && pos + 1 < n && _isDigit(src.codeUnitAt(pos + 1)))) {
        _emit(_readNumber());
        continue;
      }
      final three = pos + 3 <= n ? src.substring(pos, pos + 3) : '';
      final two = pos + 2 <= n ? src.substring(pos, pos + 2) : '';
      if (three == '**=' || three == '//=') {
        pos += 3;
        _emit(_Tok(_Tk.op, three, line: line));
        continue;
      }
      if (const {'**', '//', '==', '!=', '<=', '>=', '+=', '-=', '*=', '/=', '%=', '->'}
          .contains(two)) {
        pos += 2;
        _emit(_Tok(_Tk.op, two, line: line));
        continue;
      }
      final ch = String.fromCharCode(c);
      if ('+-*/%=<>()[]{}.,:;!&|^~@'.contains(ch)) {
        pos++;
        if (ch == '(' || ch == '[' || ch == '{') bracketDepth++;
        if (ch == ')' || ch == ']' || ch == '}') {
          if (bracketDepth > 0) bracketDepth--;
        }
        _emit(_Tok(_Tk.op, ch, line: line));
        continue;
      }
      throw PyError('Неизвестный символ: "$ch" (строка $line)');
    }
    if (tokens.isNotEmpty && tokens.last.t != _Tk.newline) {
      _emit(_Tok(_Tk.newline, '\n', line: line));
    }
    while (indents.length > 1) {
      indents.removeLast();
      _emit(_Tok(_Tk.dedent, ''));
    }
    _emit(_Tok(_Tk.eof, ''));
    return tokens;
  }

  void _emit(_Tok t) => tokens.add(t);

  void _handleIndent(int indent) {
    if (indent > indents.last) {
      indents.add(indent);
      _emit(_Tok(_Tk.indent, ''));
    } else if (indent < indents.last) {
      while (indents.length > 1 && indents.last > indent) {
        indents.removeLast();
        _emit(_Tok(_Tk.dedent, ''));
      }
      if (indents.last != indent) {
        throw PyError('Ошибка отступа (IndentationError), строка $line');
      }
    }
  }

  _Tok _readString(String prefix) {
    final quote = src[pos];
    pos++;
    final isF = prefix.toLowerCase().contains('f');
    final isRaw = prefix.toLowerCase().contains('r');
    final buf = StringBuffer();
    final n = src.length;
    while (pos < n && src[pos] != quote) {
      final ch = src[pos];
      if (ch == '\\' && !isRaw) {
        pos++;
        if (pos < n) {
          buf.write(_unescape(src[pos]));
          pos++;
        }
      } else if (ch == '\n') {
        throw PyError('Незакрытая строка (строка $line)');
      } else {
        buf.write(ch);
        pos++;
      }
    }
    if (pos >= n) throw PyError('Незакрытая строка (строка $line)');
    pos++;
    return _Tok(_Tk.str, buf.toString(), isF: isF, line: line);
  }

  String _unescape(String c) {
    switch (c) {
      case 'n':
        return '\n';
      case 't':
        return '\t';
      case 'r':
        return '\r';
      case '\\':
        return '\\';
      case "'":
        return "'";
      case '"':
        return '"';
      case '0':
        return '\u0000';
      default:
        return '\\$c';
    }
  }

  _Tok _readNumber() {
    final start = pos;
    final n = src.length;
    var isDouble = false;
    while (pos < n && _isDigit(src.codeUnitAt(pos))) {
      pos++;
    }
    if (pos < n && src[pos] == '.') {
      isDouble = true;
      pos++;
      while (pos < n && _isDigit(src.codeUnitAt(pos))) {
        pos++;
      }
    }
    if (pos < n && (src[pos] == 'e' || src[pos] == 'E')) {
      isDouble = true;
      pos++;
      if (pos < n && (src[pos] == '+' || src[pos] == '-')) pos++;
      while (pos < n && _isDigit(src.codeUnitAt(pos))) {
        pos++;
      }
    }
    final text = src.substring(start, pos);
    if (isDouble) {
      return _Tok(_Tk.num, text, lit: double.parse(text), line: line);
    }
    return _Tok(_Tk.num, text, lit: int.parse(text), line: line);
  }
}

// ---------------------------------------------------------------------------
// AST
// ---------------------------------------------------------------------------

abstract class Node {}

abstract class Stmt extends Node {}

abstract class Expr extends Node {}

class Program {
  final List<Stmt> stmts;
  Program(this.stmts);
}

class Assign extends Stmt {
  final Expr target;
  final String op; // '=' or augmented
  final Expr value;
  Assign(this.target, this.op, this.value);
}

class ExprStmt extends Stmt {
  final Expr expr;
  ExprStmt(this.expr);
}

class IfStmt extends Stmt {
  final Expr cond;
  final List<Stmt> body;
  final List<List<dynamic>> elifs;
  final List<Stmt>? orelse;
  IfStmt(this.cond, this.body, this.elifs, this.orelse);
}

class WhileStmt extends Stmt {
  final Expr cond;
  final List<Stmt> body;
  final List<Stmt>? orelse;
  WhileStmt(this.cond, this.body, this.orelse);
}

class ForStmt extends Stmt {
  final Expr target;
  final Expr iterable;
  final List<Stmt> body;
  final List<Stmt>? orelse;
  ForStmt(this.target, this.iterable, this.body, this.orelse);
}

class DefStmt extends Stmt {
  final String name;
  final List<String> params;
  final List<Expr?> defaults;
  final List<Stmt> body;
  final String? vararg;
  final String? kwarg;
  final List<String> decorators;
  DefStmt(this.name, this.params, this.defaults, this.body,
      {this.vararg, this.kwarg, List<String>? decorators})
      : decorators = decorators ?? [];
}

class ClassStmt extends Stmt {
  final String name;
  final List<Expr> bases;
  final List<Stmt> body;
  ClassStmt(this.name, this.bases, this.body);
}

class ReturnStmt extends Stmt {
  final Expr? value;
  ReturnStmt(this.value);
}

class BreakStmt extends Stmt {}

class ContinueStmt extends Stmt {}

class PassStmt extends Stmt {}

class ImportStmt extends Stmt {
  final List<List<String?>> modules; // [module, alias]
  ImportStmt(this.modules);
}

class FromImportStmt extends Stmt {
  final String module;
  final List<List<String?>> names;
  FromImportStmt(this.module, this.names);
}

class TryStmt extends Stmt {
  final List<Stmt> body;
  final String? handlerName;
  final List<Stmt> handler;
  TryStmt(this.body, this.handlerName, this.handler);
}

class NumLit extends Expr {
  final dynamic value;
  NumLit(this.value);
}

class StrLit extends Expr {
  final String value;
  StrLit(this.value);
}

class BoolLit extends Expr {
  final bool value;
  BoolLit(this.value);
}

class NoneLit extends Expr {}

class FStringExpr extends Expr {
  final List<Object> parts;
  FStringExpr(this.parts);
}

class FPart {
  final Expr expr;
  final String? spec;
  FPart(this.expr, this.spec);
}

class NameExpr extends Expr {
  final String name;
  NameExpr(this.name);
}

class ListLit extends Expr {
  final List<Expr> elements;
  ListLit(this.elements);
}

class TupleLit extends Expr {
  final List<Expr> elements;
  TupleLit(this.elements);
}

class DictLit extends Expr {
  final List<List<Expr>> pairs;
  DictLit(this.pairs);
}

class SetLit extends Expr {
  final List<Expr> elements;
  SetLit(this.elements);
}

class BinOp extends Expr {
  final String op;
  final Expr left, right;
  BinOp(this.op, this.left, this.right);
}

class UnaryOp extends Expr {
  final String op;
  final Expr operand;
  UnaryOp(this.op, this.operand);
}

class BoolOp extends Expr {
  final String op;
  final List<Expr> values;
  BoolOp(this.op, this.values);
}

class CompareExpr extends Expr {
  final Expr left;
  final List<List<dynamic>> ops; // [op, Expr]
  CompareExpr(this.left, this.ops);
}

class CondExpr extends Expr {
  final Expr cond, yes, no;
  CondExpr(this.cond, this.yes, this.no);
}

class AttrExpr extends Expr {
  final Expr obj;
  final String name;
  AttrExpr(this.obj, this.name);
}

class SubscriptExpr extends Expr {
  final Expr obj, index;
  SubscriptExpr(this.obj, this.index);
}

class SliceExpr extends Expr {
  final Expr obj;
  final Expr? start, stop, step;
  SliceExpr(this.obj, this.start, this.stop, this.step);
}

class CallExpr extends Expr {
  final Expr callee;
  final List<Expr> args;
  final List<List<dynamic>> kwargs; // [name, Expr]
  CallExpr(this.callee, this.args, this.kwargs);
}

class LambdaExpr extends Expr {
  final List<String> params;
  final List<Expr?> defaults;
  final Expr body;
  LambdaExpr(this.params, this.defaults, this.body);
}

class ListCompExpr extends Expr {
  final Expr element;
  final Expr target;
  final Expr iterable;
  final Expr? condition;
  ListCompExpr(this.element, this.target, this.iterable, this.condition);
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

class _Parser {
  final List<_Tok> toks;
  int p = 0;
  String? className;

  _Parser(this.toks);

  _Tok get cur => toks[p];
  _Tok peek([int k = 1]) => p + k < toks.length ? toks[p + k] : toks.last;
  bool _check(_Tk t) => cur.t == t;
  bool _checkOp(String s) => cur.isOp(s);
  bool _checkName(String s) => cur.isName(s);
  _Tok _next() => toks[p++];

  String _mangle(String name) {
    if (className != null &&
        name.startsWith('__') &&
        !name.endsWith('__') &&
        name.length > 2) {
      return '_${className}__${name.substring(2)}';
    }
    return name;
  }

  Program parseProgram() {
    final stmts = <Stmt>[];
    _skipNewlines();
    while (!_check(_Tk.eof)) {
      stmts.add(_statement());
      _skipNewlines();
    }
    return Program(stmts);
  }

  void _skipNewlines() {
    while (_check(_Tk.newline)) {
      _next();
    }
  }

  Stmt _statement() {
    _skipNewlines();
    if (_checkOp('@')) {
      final decos = <String>[];
      while (_checkOp('@')) {
        _next();
        final e = _postfix();
        if (e is NameExpr) decos.add(e.name);
        if (e is AttrExpr) decos.add(e.name);
        _endSimple();
      }
      final inner = _statement();
      if (inner is DefStmt) {
        inner.decorators.addAll(decos);
        return inner;
      }
      throw PyError('Декоратор применим только к def/class');
    }
    if (_checkName('if')) return _ifStmt();
    if (_checkName('while')) return _whileStmt();
    if (_checkName('for')) return _forStmt();
    if (_checkName('def')) return _defStmt(false);
    if (_checkName('class')) return _classStmt();
    if (_checkName('return')) {
      _next();
      Expr? value;
      if (!_check(_Tk.newline) && !_check(_Tk.dedent) && !_check(_Tk.eof)) {
        value = _exprList();
      }
      _endSimple();
      return ReturnStmt(value);
    }
    if (_checkName('break')) {
      _next();
      _endSimple();
      return BreakStmt();
    }
    if (_checkName('continue')) {
      _next();
      _endSimple();
      return ContinueStmt();
    }
    if (_checkName('pass')) {
      _next();
      _endSimple();
      return PassStmt();
    }
    if (_checkName('import')) return _importStmt();
    if (_checkName('from')) return _fromImportStmt();
    if (_checkName('try')) return _tryStmt();
    return _simpleStatement();
  }

  void _endSimple() {
    if (_check(_Tk.newline)) {
      _next();
    } else if (_check(_Tk.dedent) || _check(_Tk.eof)) {
      // ok
    } else {
      throw PyError('Ожидался конец строки, найдено "${cur.v}"');
    }
  }

  Stmt _simpleStatement() {
    final first = _expression();
    // tuple assignment target
    if (_checkOp(',')) {
      final targets = <Expr>[first];
      while (_checkOp(',')) {
        _next();
        if (_checkOp('=')) break;
        targets.add(_expression());
      }
      if (_checkOp('=')) {
        _next();
        final value = _exprList();
        _endSimple();
        return Assign(TupleLit(targets), '=', value);
      }
      throw PyError('Некорректное выражение');
    }
    if (_checkOp('=')) {
      _next();
      final value = _exprList();
      _endSimple();
      return Assign(first, '=', value);
    }
    const augs = ['+=', '-=', '*=', '/=', '//=', '%=', '**='];
    if (cur.t == _Tk.op && augs.contains(cur.v)) {
      final op = _next().v;
      final value = _exprList();
      _endSimple();
      return Assign(first, op, value);
    }
    _endSimple();
    return ExprStmt(first);
  }

  Expr _exprList() {
    final first = _expression();
    if (!_checkOp(',')) return first;
    final items = <Expr>[first];
    while (_checkOp(',')) {
      _next();
      if (_check(_Tk.newline) || _check(_Tk.dedent) || _check(_Tk.eof) || _checkOp(')') || _checkOp(']') || _checkOp('}')) {
        break;
      }
      items.add(_expression());
    }
    return TupleLit(items);
  }

  List<Stmt> _suite() {
    if (!_checkOp(':')) throw PyError('Ожидался ":"');
    _next();
    final stmts = <Stmt>[];
    if (_check(_Tk.newline)) {
      _next();
      _skipNewlines();
      if (_check(_Tk.indent)) {
        _next();
        while (!_check(_Tk.dedent) && !_check(_Tk.eof)) {
          _skipNewlines();
          if (_check(_Tk.dedent) || _check(_Tk.eof)) break;
          stmts.add(_statement());
        }
        if (_check(_Tk.dedent)) _next();
      }
    } else {
      stmts.add(_simpleStatement());
    }
    return stmts;
  }

  Stmt _ifStmt() {
    _next();
    final cond = _expression();
    final body = _suite();
    final elifs = <List<dynamic>>[];
    List<Stmt>? orelse;
    while (_checkName('elif')) {
      _next();
      final c = _expression();
      final b = _suite();
      elifs.add([c, b]);
    }
    if (_checkName('else')) {
      _next();
      orelse = _suite();
    }
    return IfStmt(cond, body, elifs, orelse);
  }

  Stmt _whileStmt() {
    _next();
    final cond = _expression();
    final body = _suite();
    List<Stmt>? orelse;
    if (_checkName('else')) {
      _next();
      orelse = _suite();
    }
    return WhileStmt(cond, body, orelse);
  }

  Stmt _forStmt() {
    _next();
    final target = _target();
    if (!_checkName('in')) throw PyError('Ожидался "in" в цикле for');
    _next();
    final iterable = _expression();
    final body = _suite();
    List<Stmt>? orelse;
    if (_checkName('else')) {
      _next();
      orelse = _suite();
    }
    return ForStmt(target, iterable, body, orelse);
  }

  Expr _target() {
    final first = _postfix();
    if (!_checkOp(',')) return first;
    final items = <Expr>[first];
    while (_checkOp(',')) {
      _next();
      if (_checkName('in') || _checkOp('=')) break;
      items.add(_postfix());
    }
    return TupleLit(items);
  }

  Stmt _defStmt(bool inClass) {
    _next();
    if (!_check(_Tk.name)) throw PyError('Ожидалось имя функции');
    final name = _mangle(_next().v);
    final params = _params();
    if (_checkOp('->')) {
      _next();
      _expression();
    }
    final body = _suite();
    final defaults = params[1];
    return DefStmt(name, params[0] as List<String>, defaults as List<Expr?>, body,
        vararg: params[2] as String?, kwarg: params[3] as String?);
  }

  List<dynamic> _params() {
    if (!_checkOp('(')) throw PyError('Ожидался "("');
    _next();
    final names = <String>[];
    final defaults = <Expr?>[];
    String? vararg;
    String? kwarg;
    while (!_checkOp(')') && !_check(_Tk.eof)) {
      if (_checkOp('**') || _checkOp('*')) {
        final isKw = _checkOp('**');
        _next();
        if (_check(_Tk.name)) {
          if (isKw) {
            kwarg = _next().v;
          } else {
            vararg = _next().v;
          }
        }
        if (_checkOp(':')) {
          _next();
          _expression();
        }
        if (_checkOp(',')) {
          _next();
        }
        continue;
      }
      if (_check(_Tk.name)) {
        final n = _next().v;
        if (_checkOp(':')) {
          _next();
          _expression();
        }
        Expr? def;
        if (_checkOp('=')) {
          _next();
          def = _expression();
        }
        names.add(n);
        defaults.add(def);
      } else {
        throw PyError('Некорректный параметр "${cur.v}"');
      }
      if (_checkOp(',')) {
        _next();
      }
    }
    if (_checkOp(')')) _next();
    return [names, defaults, vararg, kwarg];
  }

  Stmt _classStmt() {
    _next();
    if (!_check(_Tk.name)) throw PyError('Ожидалось имя класса');
    final name = _next().v;
    final bases = <Expr>[];
    if (_checkOp('(')) {
      _next();
      while (!_checkOp(')') && !_check(_Tk.eof)) {
        bases.add(_expression());
        if (_checkOp(',')) _next();
      }
      if (_checkOp(')')) _next();
    }
    final saved = className;
    className = name;
    final body = _suite();
    className = saved;
    return ClassStmt(name, bases, body);
  }

  Stmt _importStmt() {
    _next();
    final modules = <List<String?>>[];
    while (true) {
      if (!_check(_Tk.name)) throw PyError('Ожидалось имя модуля');
      var mod = _next().v;
      while (_checkOp('.')) {
        _next();
        mod += '.${_next().v}';
      }
      String? alias;
      if (_checkName('as')) {
        _next();
        alias = _next().v;
      }
      modules.add([mod, alias]);
      if (_checkOp(',')) {
        _next();
        continue;
      }
      break;
    }
    _endSimple();
    return ImportStmt(modules);
  }

  Stmt _fromImportStmt() {
    _next();
    var mod = _next().v;
    while (_checkOp('.')) {
      _next();
      mod += '.${_next().v}';
    }
    if (!_checkName('import')) throw PyError('Ожидался "import"');
    _next();
    final names = <List<String?>>[];
    if (_checkOp('*')) {
      _next();
      names.add(['*', null]);
    } else {
      while (true) {
        final n = _next().v;
        String? alias;
        if (_checkName('as')) {
          _next();
          alias = _next().v;
        }
        names.add([n, alias]);
        if (_checkOp(',')) {
          _next();
          continue;
        }
        break;
      }
    }
    _endSimple();
    return FromImportStmt(mod, names);
  }

  Stmt _tryStmt() {
    _next();
    final body = _suite();
    String? handlerName;
    var handler = <Stmt>[];
    if (_checkName('except')) {
      _next();
      if (!_checkOp(':')) {
        // exception type expression (ignored semantics)
        _expression();
        if (_checkName('as')) {
          _next();
          handlerName = _next().v;
        }
      }
      handler = _suite();
    }
    return TryStmt(body, handlerName, handler);
  }

  // ---- expressions ----
  Expr _expression() {
    final e = _orExpr();
    if (_checkName('if')) {
      _next();
      final cond = _orExpr();
      if (!_checkName('else')) throw PyError('Ожидался "else"');
      _next();
      final no = _expression();
      return CondExpr(cond, e, no);
    }
    return e;
  }

  Expr _orExpr() {
    var left = _andExpr();
    if (_checkName('or')) {
      final values = <Expr>[left];
      while (_checkName('or')) {
        _next();
        values.add(_andExpr());
      }
      return BoolOp('or', values);
    }
    return left;
  }

  Expr _andExpr() {
    final left = _notExpr();
    if (_checkName('and')) {
      final values = <Expr>[left];
      while (_checkName('and')) {
        _next();
        values.add(_notExpr());
      }
      return BoolOp('and', values);
    }
    return left;
  }

  Expr _notExpr() {
    if (_checkName('not')) {
      _next();
      return UnaryOp('not', _notExpr());
    }
    return _comparison();
  }

  Expr _comparison() {
    final left = _addExpr();
    final ops = <List<dynamic>>[];
    while (true) {
      String? op;
      if (_checkOp('==') ||
          _checkOp('!=') ||
          _checkOp('<') ||
          _checkOp('>') ||
          _checkOp('<=') ||
          _checkOp('>=')) {
        op = _next().v;
      } else if (_checkName('in')) {
        _next();
        op = 'in';
      } else if (_checkName('not') && peek().isName('in')) {
        _next();
        _next();
        op = 'not in';
      } else {
        break;
      }
      final right = _addExpr();
      ops.add([op, right]);
    }
    if (ops.isEmpty) return left;
    return CompareExpr(left, ops);
  }

  Expr _addExpr() {
    var left = _mulExpr();
    while (_checkOp('+') || _checkOp('-')) {
      final op = _next().v;
      final right = _mulExpr();
      left = BinOp(op, left, right);
    }
    return left;
  }

  Expr _mulExpr() {
    var left = _unaryExpr();
    while (_checkOp('*') || _checkOp('/') || _checkOp('//') || _checkOp('%')) {
      final op = _next().v;
      final right = _unaryExpr();
      left = BinOp(op, left, right);
    }
    return left;
  }

  Expr _unaryExpr() {
    if (_checkOp('-') || _checkOp('+')) {
      final op = _next().v;
      return UnaryOp(op, _unaryExpr());
    }
    return _powerExpr();
  }

  Expr _powerExpr() {
    final base = _postfix();
    if (_checkOp('**')) {
      _next();
      final right = _unaryExpr();
      return BinOp('**', base, right);
    }
    return base;
  }

  Expr _postfix() {
    var e = _atom();
    while (true) {
      if (_checkOp('.')) {
        _next();
        final name = _mangle(_next().v);
        e = AttrExpr(e, name);
      } else if (_checkOp('[')) {
        _next();
        e = _subscript(e);
      } else if (_checkOp('(')) {
        _next();
        e = _callArgs(e);
      } else {
        break;
      }
    }
    return e;
  }

  Expr _subscript(Expr obj) {
    Expr? start;
    Expr? stop;
    Expr? step;
    var isSlice = false;
    if (_checkOp(':')) {
      isSlice = true;
    } else {
      start = _expression();
    }
    if (_checkOp(':')) {
      isSlice = true;
      _next();
      if (!_checkOp(']') && !_checkOp(':')) stop = _expression();
      if (_checkOp(':')) {
        _next();
        if (!_checkOp(']')) step = _expression();
      }
    }
    if (!_checkOp(']')) throw PyError('Ожидался "]"');
    _next();
    if (isSlice) return SliceExpr(obj, start, stop, step);
    return SubscriptExpr(obj, start!);
  }

  Expr _genExprFrom(Expr first) {
    if (!_checkName('for')) return first;
    _next();
    final target = _target();
    if (!_checkName('in')) throw PyError('Ожидался "in"');
    _next();
    final iterable = _orExpr();
    Expr? cond;
    if (_checkName('if')) {
      _next();
      cond = _orExpr();
    }
    return ListCompExpr(first, target, iterable, cond);
  }

  Expr _callArgs(Expr callee) {
    final args = <Expr>[];
    final kwargs = <List<dynamic>>[];
    while (!_checkOp(')') && !_check(_Tk.eof)) {
      if (_check(_Tk.name) && peek().isOp('=')) {
        final name = _next().v;
        _next();
        kwargs.add([name, _genExprFrom(_expression())]);
      } else {
        args.add(_genExprFrom(_expression()));
      }
      if (_checkOp(',')) {
        _next();
      } else {
        break;
      }
    }
    if (!_checkOp(')')) throw PyError('Ожидался ")"');
    _next();
    return CallExpr(callee, args, kwargs);
  }

  Expr _atom() {
    final t = cur;
    if (t.t == _Tk.num) {
      _next();
      return NumLit(t.lit);
    }
    if (t.t == _Tk.str) {
      _next();
      if (t.isF) return _parseFString(t.v);
      return StrLit(t.v);
    }
    if (t.t == _Tk.name) {
      if (t.v == 'True' || t.v == 'False') {
        _next();
        return BoolLit(t.v == 'True');
      }
      if (t.v == 'None') {
        _next();
        return NoneLit();
      }
      if (t.v == 'lambda') {
        _next();
        final params = _lambdaParams();
        if (!_checkOp(':')) throw PyError('Ожидался ":" в lambda');
        _next();
        final body = _expression();
        return LambdaExpr(params.$1, params.$2, body);
      }
      _next();
      return NameExpr(_mangle(t.v));
    }
    if (t.isOp('(')) {
      _next();
      if (_checkOp(')')) {
        _next();
        return TupleLit([]);
      }
      final first = _expression();
      if (_checkName('for')) {
        final g = _genExprFrom(first);
        if (!_checkOp(')')) throw PyError('Ожидался ")"');
        _next();
        return g;
      }
      if (_checkOp(',')) {
        final items = <Expr>[first];
        while (_checkOp(',')) {
          _next();
          if (_checkOp(')')) break;
          items.add(_expression());
        }
        if (_checkOp(')')) _next();
        return TupleLit(items);
      }
      if (!_checkOp(')')) throw PyError('Ожидался ")"');
      _next();
      return first;
    }
    if (t.isOp('[')) {
      _next();
      if (_checkOp(']')) {
        _next();
        return ListLit([]);
      }
      final first = _expression();
      if (_checkName('for')) {
        _next();
        final target = _target();
        if (!_checkName('in')) throw PyError('Ожидался "in"');
        _next();
        final iterable = _orExpr();
        Expr? cond;
        if (_checkName('if')) {
          _next();
          cond = _orExpr();
        }
        if (!_checkOp(']')) throw PyError('Ожидался "]"');
        _next();
        return ListCompExpr(first, target, iterable, cond);
      }
      final items = <Expr>[first];
      while (_checkOp(',')) {
        _next();
        if (_checkOp(']')) break;
        items.add(_expression());
      }
      if (!_checkOp(']')) throw PyError('Ожидался "]"');
      _next();
      return ListLit(items);
    }
    if (t.isOp('{')) {
      _next();
      if (_checkOp('}')) {
        _next();
        return DictLit([]);
      }
      final first = _expression();
      if (_checkOp(':')) {
        _next();
        final firstVal = _expression();
        final pairs = <List<Expr>>[
          [first, firstVal]
        ];
        while (_checkOp(',')) {
          _next();
          if (_checkOp('}')) break;
          final k = _expression();
          if (!_checkOp(':')) throw PyError('Ожидался ":"');
          _next();
          final v = _expression();
          pairs.add([k, v]);
        }
        if (!_checkOp('}')) throw PyError('Ожидался "}"');
        _next();
        return DictLit(pairs);
      }
      final items = <Expr>[first];
      while (_checkOp(',')) {
        _next();
        if (_checkOp('}')) break;
        items.add(_expression());
      }
      if (!_checkOp('}')) throw PyError('Ожидался "}"');
      _next();
      return SetLit(items);
    }
    throw PyError('Неожиданный токен "${cur.v}"');
  }

  (List<String>, List<Expr?>) _lambdaParams() {
    final names = <String>[];
    final defaults = <Expr?>[];
    while (_check(_Tk.name)) {
      final n = _next().v;
      Expr? def;
      if (_checkOp('=')) {
        _next();
        def = _expression();
      }
      names.add(n);
      defaults.add(def);
      if (_checkOp(',')) {
        _next();
      } else {
        break;
      }
    }
    return (names, defaults);
  }

  Expr _parseFString(String content) {
    final parts = <Object>[];
    final buf = StringBuffer();
    var i = 0;
    while (i < content.length) {
      final c = content[i];
      if (c == '{') {
        if (i + 1 < content.length && content[i + 1] == '{') {
          buf.write('{');
          i += 2;
          continue;
        }
        var j = i + 1;
        var colon = -1;
        while (j < content.length && content[j] != '}') {
          if (content[j] == ':' && colon == -1) colon = j;
          j++;
        }
        if (j >= content.length) throw PyError('Незакрытая "{" в f-строке');
        final exprText =
            colon == -1 ? content.substring(i + 1, j) : content.substring(i + 1, colon);
        final specText = colon == -1 ? null : content.substring(colon + 1, j);
        if (buf.isNotEmpty) {
          parts.add(buf.toString());
          buf.clear();
        }
        parts.add(FPart(_parseInlineExpr(exprText.trim()), specText));
        i = j + 1;
      } else if (c == '}') {
        if (i + 1 < content.length && content[i + 1] == '}') {
          buf.write('}');
          i += 2;
          continue;
        }
        buf.write('}');
        i++;
      } else {
        buf.write(c);
        i++;
      }
    }
    if (buf.isNotEmpty) parts.add(buf.toString());
    return FStringExpr(parts);
  }

  Expr _parseInlineExpr(String s) {
    final tokens = _Lexer('__fexpr__ = $s').tokenize();
    final program = _Parser(tokens).parseProgram();
    final stmt = program.stmts.first;
    if (stmt is Assign) return stmt.value;
    throw PyError('Некорректное выражение в f-строке');
  }
}

// ---------------------------------------------------------------------------
// Runtime
// ---------------------------------------------------------------------------

class _Scope {
  final Map<String, dynamic> vars = {};
  final _Scope? parent;
  _Scope(this.parent);
}

class _Return implements Exception {
  final dynamic value;
  _Return(this.value);
}

class _Break implements Exception {}

class _Continue implements Exception {}

class _Interp {
  final StringBuffer out = StringBuffer();
  late _Scope global;
  final List<String> _stdin;
  int _stdinPos = 0;
  int inputsMissing = 0;
  late final DateTime _start;
  int _ops = 0;
  final Map<String, PyNamespace> _modules = {};
  math.Random _rng;
  _Scope? currentClassScope;
  final List<PyClass> _classStack = [];

  _Interp(String stdin, [int? seed]) : _stdin = _splitStdin(stdin),
        _rng = math.Random(seed) {
    _start = DateTime.now();
    global = _Scope(null);
  }

  static List<String> _splitStdin(String stdin) {
    if (stdin.isEmpty) return <String>[];
    final lines = stdin.split('\n');
    if (stdin.endsWith('\n') && lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }
    return lines;
  }

  void _tick() {
    _ops++;
    if (_ops > 4000000) {
      throw PyError('Превышен лимит выполнения (возможно, бесконечный цикл)');
    }
    if ((_ops & 0x3FFF) == 0 &&
        DateTime.now().difference(_start).inMilliseconds > 3000) {
      throw PyError('Программа выполняется слишком долго (возможно, бесконечный цикл)');
    }
  }

  void execProgram(Program program) {
    for (final s in program.stmts) {
      _exec(s, global);
    }
  }

  void _exec(Stmt stmt, _Scope scope) {
    _tick();
    if (stmt is ExprStmt) {
      _eval(stmt.expr, scope);
    } else if (stmt is Assign) {
      _execAssign(stmt, scope);
    } else if (stmt is IfStmt) {
      if (_truthy(_eval(stmt.cond, scope))) {
        _execBlock(stmt.body, scope);
      } else {
        var done = false;
        for (final e in stmt.elifs) {
          if (_truthy(_eval(e[0] as Expr, scope))) {
            _execBlock(e[1] as List<Stmt>, scope);
            done = true;
            break;
          }
        }
        if (!done && stmt.orelse != null) {
          _execBlock(stmt.orelse!, scope);
        }
      }
    } else if (stmt is WhileStmt) {
      var broke = false;
      while (_truthy(_eval(stmt.cond, scope))) {
        _tick();
        try {
          _execBlock(stmt.body, scope);
        } on _Break {
          broke = true;
          break;
        } on _Continue {
          continue;
        }
      }
      if (!broke && stmt.orelse != null) _execBlock(stmt.orelse!, scope);
    } else if (stmt is ForStmt) {
      final iterable = _eval(stmt.iterable, scope);
      final items = _iterate(iterable);
      var broke = false;
      for (final item in items) {
        _tick();
        _assign(stmt.target, item, scope);
        try {
          _execBlock(stmt.body, scope);
        } on _Break {
          broke = true;
          break;
        } on _Continue {
          continue;
        }
      }
      if (!broke && stmt.orelse != null) _execBlock(stmt.orelse!, scope);
    } else if (stmt is DefStmt) {
      scope.vars[stmt.name] = _makeFunction(stmt, scope);
    } else if (stmt is ClassStmt) {
      _execClass(stmt, scope);
    } else if (stmt is ReturnStmt) {
      throw _Return(stmt.value == null ? pyNone : _eval(stmt.value!, scope));
    } else if (stmt is BreakStmt) {
      throw _Break();
    } else if (stmt is ContinueStmt) {
      throw _Continue();
    } else if (stmt is PassStmt) {
      // nothing
    } else if (stmt is ImportStmt) {
      for (final m in stmt.modules) {
        final name = m[0]!;
        final ns = _importModule(name);
        scope.vars[m[1] ?? name.split('.').first] = ns;
      }
    } else if (stmt is FromImportStmt) {
      final ns = _importModule(stmt.module);
      for (final n in stmt.names) {
        final name = n[0]!;
        if (name == '*') {
          scope.vars.addAll(ns.attrs);
        } else {
          if (!ns.attrs.containsKey(name)) {
            throw PyError(
                "cannot import name '$name' from '${stmt.module}'");
          }
          scope.vars[n[1] ?? name] = ns.attrs[name];
        }
      }
    } else if (stmt is TryStmt) {
      try {
        _execBlock(stmt.body, scope);
      } on _Return {
        rethrow;
      } on _Break {
        rethrow;
      } on _Continue {
        rethrow;
      } catch (e) {
        if (stmt.handlerName != null) {
          scope.vars[stmt.handlerName!] = _str(e);
        }
        _execBlock(stmt.handler, scope);
      }
    } else {
      throw PyError('Неизвестная инструкция');
    }
  }

  void _execBlock(List<Stmt> stmts, _Scope scope) {
    for (final s in stmts) {
      _exec(s, scope);
    }
  }

  PyFunction _makeFunction(DefStmt stmt, _Scope scope) {
    final defaults = <dynamic>[];
    for (final d in stmt.defaults) {
      defaults.add(d == null ? _noDefault : _eval(d, scope));
    }
    final fn = PyFunction(
      name: stmt.name,
      params: stmt.params,
      defaults: defaults,
      defaultCount: stmt.defaults.where((d) => d != null).length,
      body: stmt.body,
      closure: scope,
    );
    fn.vararg = stmt.vararg;
    fn.kwarg = stmt.kwarg;
    fn.isStatic = stmt.decorators.contains('staticmethod');
    fn.isProperty = stmt.decorators.contains('property');
    return fn;
  }

  static const _noDefault = Object();

  void _execClass(ClassStmt stmt, _Scope scope) {
    final bases = <PyClass>[];
    for (final b in stmt.bases) {
      final v = _eval(b, scope);
      if (v is PyClass) bases.add(v);
    }
    final cls = PyClass(stmt.name, bases);
    final classScope = _Scope(scope);
    _classStack.add(cls);
    _execBlock(stmt.body, classScope);
    _classStack.removeLast();
    for (final entry in classScope.vars.entries) {
      final v = entry.value;
      if (v is PyFunction) {
        v.owner = cls;
        cls.methods[entry.key] = v;
      } else {
        cls.classAttrs[entry.key] = v;
      }
    }
    scope.vars[stmt.name] = cls;
  }

  void _execAssign(Assign stmt, _Scope scope) {
    if (stmt.op == '=') {
      final value = _eval(stmt.value, scope);
      _assign(stmt.target, value, scope);
      return;
    }
    final current = _eval(stmt.target, scope);
    final rhs = _eval(stmt.value, scope);
    final op = stmt.op.substring(0, stmt.op.length - 1);
    final value = _binop(op, current, rhs);
    _assign(stmt.target, value, scope);
  }

  void _assign(Expr target, dynamic value, _Scope scope) {
    if (target is NameExpr) {
      scope.vars[target.name] = value;
    } else if (target is TupleLit || target is ListLit) {
      final targets = target is TupleLit
          ? target.elements
          : (target as ListLit).elements;
      final items = _iterate(value);
      for (var i = 0; i < targets.length; i++) {
        _assign(targets[i], i < items.length ? items[i] : pyNone, scope);
      }
    } else if (target is AttrExpr) {
      final obj = _eval(target.obj, scope);
      _setAttr(obj, target.name, value);
    } else if (target is SubscriptExpr) {
      final obj = _eval(target.obj, scope);
      final idx = _eval(target.index, scope);
      _setIndex(obj, idx, value);
    } else {
      throw PyError('Некорректная цель присваивания');
    }
  }

  // ---- expressions ----
  dynamic _eval(Expr e, _Scope scope) {
    _tick();
    if (e is NumLit) return e.value;
    if (e is StrLit) return e.value;
    if (e is BoolLit) return e.value;
    if (e is NoneLit) return pyNone;
    if (e is FStringExpr) {
      final buf = StringBuffer();
      for (final part in e.parts) {
        if (part is String) {
          buf.write(part);
        } else if (part is FPart) {
          buf.write(_formatValue(_eval(part.expr, scope), part.spec));
        }
      }
      return buf.toString();
    }
    if (e is NameExpr) return _lookup(e.name, scope);
    if (e is ListLit) {
      return PyList(e.elements.map((x) => _eval(x, scope)).toList());
    }
    if (e is TupleLit) {
      return PyTuple(e.elements.map((x) => _eval(x, scope)).toList());
    }
    if (e is DictLit) {
      final d = PyDict();
      for (final pair in e.pairs) {
        final k = _eval(pair[0], scope);
        final v = _eval(pair[1], scope);
        _dictSet(d, k, v);
      }
      return d;
    }
    if (e is SetLit) {
      final s = PySet();
      for (final x in e.elements) {
        final v = _eval(x, scope);
        if (!_setHas(s, v)) s.items.add(v);
      }
      return s;
    }
    if (e is BinOp) return _binop(e.op, _eval(e.left, scope), _eval(e.right, scope));
    if (e is UnaryOp) {
      if (e.op == 'not') return !_truthy(_eval(e.operand, scope));
      final v = _eval(e.operand, scope);
      if (e.op == '-') {
        if (v is int) return -v;
        if (v is double) return -v;
        throw PyError('Унарный минус применим только к числам');
      }
      return v;
    }
    if (e is BoolOp) {
      dynamic result = true;
      for (final v in e.values) {
        result = _eval(v, scope);
        if (e.op == 'and' && !_truthy(result)) return result;
        if (e.op == 'or' && _truthy(result)) return result;
      }
      return result;
    }
    if (e is CompareExpr) {
      dynamic left = _eval(e.left, scope);
      for (final pair in e.ops) {
        final right = _eval(pair[1] as Expr, scope);
        if (!_compare(pair[0] as String, left, right)) return false;
        left = right;
      }
      return true;
    }
    if (e is CondExpr) {
      return _truthy(_eval(e.cond, scope))
          ? _eval(e.yes, scope)
          : _eval(e.no, scope);
    }
    if (e is AttrExpr) return _getAttr(_eval(e.obj, scope), e.name);
    if (e is SubscriptExpr) {
      return _index(_eval(e.obj, scope), _eval(e.index, scope));
    }
    if (e is SliceExpr) {
      final obj = _eval(e.obj, scope);
      final start = e.start == null ? null : _eval(e.start!, scope) as int?;
      final stop = e.stop == null ? null : _eval(e.stop!, scope) as int?;
      final step = e.step == null ? null : _eval(e.step!, scope) as int?;
      return _slice(obj, start, stop, step);
    }
    if (e is CallExpr) {
      dynamic callee;
      final calleeExpr = e.callee;
      final args = <dynamic>[];
      final kwargs = <String, dynamic>{};
      if (calleeExpr is AttrExpr) {
        final obj = _eval(calleeExpr.obj, scope);
        callee = _getAttr(obj, calleeExpr.name);
      } else {
        callee = _eval(calleeExpr, scope);
      }
      for (final a in e.args) {
        args.add(_eval(a, scope));
      }
      for (final kw in e.kwargs) {
        kwargs[kw[0] as String] = _eval(kw[1] as Expr, scope);
      }
      return _callValue(callee, args, kwargs);
    }
    if (e is LambdaExpr) {
      final defaults = <dynamic>[];
      for (final d in e.defaults) {
        defaults.add(d == null ? _noDefault : _eval(d, scope));
      }
      return PyFunction(
        name: '<lambda>',
        params: e.params,
        defaults: defaults,
        defaultCount: e.defaults.where((d) => d != null).length,
        body: const [],
        exprBody: e.body,
        closure: scope,
      );
    }
    if (e is ListCompExpr) {
      final result = <dynamic>[];
      final items = _iterate(_eval(e.iterable, scope));
      for (final item in items) {
        _tick();
        _assign(e.target, item, scope);
        if (e.condition != null && !_truthy(_eval(e.condition!, scope))) {
          continue;
        }
        result.add(_eval(e.element, scope));
      }
      return PyList(result);
    }
    throw PyError('Неподдерживаемое выражение');
  }

  dynamic _lookup(String name, _Scope scope) {
    _Scope? s = scope;
    while (s != null) {
      if (s.vars.containsKey(name)) return s.vars[name];
      s = s.parent;
    }
    final b = _builtin(name);
    if (b != null) return b;
    throw PyError("name '$name' is not defined");
  }

  // ---- attribute access ----
  dynamic _getAttr(dynamic obj, String name) {
    if (obj is PyInstance) {
      if (obj.attrs.containsKey(name)) return obj.attrs[name];
      final m = _findMethod(obj.cls, name);
      if (m != null) {
        if (m.isStatic) return m;
        if (m.isProperty) return _invokeFunction(m, [obj], {});
        return PyBoundMethod(obj, m);
      }
      final ca = _findClassAttr(obj.cls, name);
      if (ca != _notFound) return ca;
      throw PyError(
          "'${obj.cls.name}' object has no attribute '$name'");
    }
    if (obj is PySuper) {
      final m = _findMethodInBases(obj.startClass, name);
      if (m != null) return PyBoundMethod(obj.instance, m);
      throw PyError("'super' object has no attribute '$name'");
    }
    if (obj is PyClass) {
      if (obj.classAttrs.containsKey(name)) return obj.classAttrs[name];
      final m = _findMethod(obj, name);
      if (m != null) return m;
      throw PyError("type object '${obj.name}' has no attribute '$name'");
    }
    if (obj is PyNamespace) {
      if (obj.attrs.containsKey(name)) return obj.attrs[name];
      throw PyError("module '${obj.name}' has no attribute '$name'");
    }
    if (obj is PyResponse) {
      switch (name) {
        case 'status_code':
          return obj.statusCode;
        case 'reason':
          return obj.reason;
        case 'url':
          return obj.url;
        case 'headers':
          return obj.headers;
        case 'text':
          return _jsonEncodePy(obj.payload);
        case 'json':
          return PyBuiltin('json', (a, k) => obj.payload);
        case 'raise_for_status':
          return PyBuiltin('raise_for_status', (a, k) {
            if (obj.statusCode >= 400) {
              throw PyError('${obj.statusCode} Client Error: ${obj.reason}');
            }
            return pyNone;
          });
      }
      throw PyError("'Response' object has no attribute '$name'");
    }
    if (obj is String) {
      final b = _stringMethod(obj, name);
      if (b != null) return b;
    }
    if (obj is PyList) {
      final b = _listMethod(obj, name);
      if (b != null) return b;
    }
    if (obj is PyDict) {
      final b = _dictMethod(obj, name);
      if (b != null) return b;
    }
    if (obj is PySet) {
      final b = _setMethod(obj, name);
      if (b != null) return b;
    }
    if (obj is PyTuple) {
      final b = _tupleMethod(obj, name);
      if (b != null) return b;
    }
    throw PyError("'${_typeName(obj)}' object has no attribute '$name'");
  }

  static final Object _notFound = Object();

  PyFunction? _findMethod(PyClass cls, String name) {
    var c = cls;
    final seen = <PyClass>{};
    while (true) {
      if (c.methods.containsKey(name)) return c.methods[name];
      final attr = c.classAttrs[name];
      if (attr is PyFunction) return attr;
      PyClass? next;
      for (final b in c.bases) {
        if (seen.add(b)) {
          next = b;
          break;
        }
      }
      if (next == null) return null;
      c = next;
    }
  }

  PyFunction? _findMethodInBases(PyClass cls, String name) {
    for (final base in cls.bases) {
      final m = _findMethod(base, name);
      if (m != null) return m;
    }
    return null;
  }

  dynamic _findClassAttr(PyClass cls, String name) {    var c = cls;
    final seen = <PyClass>{};
    while (true) {
      if (c.classAttrs.containsKey(name)) return c.classAttrs[name];
      PyClass? next;
      for (final b in c.bases) {
        if (seen.add(b)) {
          next = b;
          break;
        }
      }
      if (next == null) return _notFound;
      c = next;
    }
  }

  void _setAttr(dynamic obj, String name, dynamic value) {
    if (obj is PyInstance) {
      obj.attrs[name] = value;
      return;
    }
    if (obj is PyNamespace) {
      obj.attrs[name] = value;
      return;
    }
    if (obj is PyClass) {
      obj.classAttrs[name] = value;
      return;
    }
    throw PyError("'${_typeName(obj)}' object does not support attribute assignment");
  }

  // ---- calls ----
  dynamic _callValue(dynamic callee, List<dynamic> args, Map<String, dynamic> kwargs) {
    _tick();
    if (callee is PyBuiltin) return callee.fn(args, kwargs);
    if (callee is PyBoundBuiltin) return callee.fn(callee.target, args, kwargs);
    if (callee is PyBoundMethod) {
      return _invokeFunction(
          callee.method as PyFunction, [callee.target, ...args], kwargs);
    }
    if (callee is PyFunction) return _invokeFunction(callee, args, kwargs);
    if (callee is PyClass) {
      final inst = PyInstance(callee);
      final init = _findMethod(callee, '__init__');
      if (init != null) {
        _invokeFunction(init, [inst, ...args], kwargs);
      } else if (args.isNotEmpty) {
        throw PyError('${callee.name}() takes no arguments');
      }
      return inst;
    }
    throw PyError("'${_typeName(callee)}' object is not callable");
  }

  PyInstance? _currentInstance;
  PyClass? _currentClass;

  dynamic _invokeFunction(PyFunction fn, List<dynamic> args,
      Map<String, dynamic> kwargs) {
    final scope = _Scope(fn.closure);
    final positional = <dynamic>[...args];
    for (var i = 0; i < fn.params.length; i++) {
      final name = fn.params[i];
      if (i < positional.length) {
        scope.vars[name] = positional[i];
      } else if (kwargs.containsKey(name)) {
        scope.vars[name] = kwargs[name];
      } else if (fn.defaults[i] != _noDefault) {
        scope.vars[name] = fn.defaults[i];
      } else {
        throw PyError("${fn.name}() missing required argument: '$name'");
      }
    }
    if (fn.vararg != null) {
      scope.vars[fn.vararg!] = PyList(
          positional.length > fn.params.length
              ? positional.sublist(fn.params.length)
              : <dynamic>[]);
    } else if (positional.length > fn.params.length) {
      throw PyError(
          "${fn.name}() takes ${fn.params.length} positional argument(s) but ${positional.length} were given");
    }
    final extraKwargs = <String, dynamic>{};
    for (final k in kwargs.keys) {
      if (!fn.params.contains(k)) {
        if (fn.kwarg != null) {
          extraKwargs[k] = kwargs[k];
        } else {
          throw PyError("${fn.name}() got an unexpected keyword argument '$k'");
        }
      }
    }
    if (fn.kwarg != null) {
      final d = PyDict();
      extraKwargs.forEach((k, v) => d.entries.add([k, v]));
      scope.vars[fn.kwarg!] = d;
    }
    final savedInstance = _currentInstance;
    final savedClass = _currentClass;
    if (fn.owner != null && args.isNotEmpty && args.first is PyInstance) {
      _currentInstance = args.first as PyInstance;
      _currentClass = fn.owner;
    }
    try {
      if (fn.exprBody != null) {
        return _eval(fn.exprBody!, scope);
      }
      try {
        _execBlock(fn.body, scope);
      } on _Return catch (r) {
        return r.value;
      }
      return pyNone;
    } finally {
      _currentInstance = savedInstance;
      _currentClass = savedClass;
    }
  }

  // ---- builtins ----
  PyBuiltin? _builtin(String name) {
    switch (name) {
      case 'print':
        return PyBuiltin('print', (args, kwargs) {
          final sep = kwargs.containsKey('sep') ? _str(kwargs['sep']) : ' ';
          final end = kwargs.containsKey('end') ? _str(kwargs['end']) : '\n';
          out.write(args.map(_str).join(sep));
          out.write(end);
          return pyNone;
        });
      case 'input':
        return PyBuiltin('input', (args, kwargs) {
          if (args.isNotEmpty) out.write(_str(args[0]));
          if (_stdinPos < _stdin.length) {
            var line = _stdin[_stdinPos++];
            if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
            return line;
          }
          inputsMissing++;
          return '';
        });
      case 'len':
        return PyBuiltin('len', (args, kwargs) => _len(args[0]));
      case 'range':
        return PyBuiltin('range', (args, kwargs) {
          final nums = args.map((a) => _asInt(a)).toList();
          if (nums.length == 1) return PyRange(0, nums[0], 1);
          if (nums.length == 2) return PyRange(nums[0], nums[1], 1);
          if (nums.length == 3) return PyRange(nums[0], nums[1], nums[2]);
          throw PyError('range() требует 1-3 аргумента');
        });
      case 'min':
        return PyBuiltin('min', (args, kwargs) => _minmax(args, true, kwargs));
      case 'max':
        return PyBuiltin('max', (args, kwargs) => _minmax(args, false, kwargs));
      case 'sum':
        return PyBuiltin('sum', (args, kwargs) {
          final items = _iterate(args[0]);
          dynamic total = args.length > 1 ? args[1] : 0;
          for (final x in items) {
            total = _binop('+', total, x);
          }
          return total;
        });
      case 'sorted':
        return PyBuiltin('sorted', (args, kwargs) {
          var items = _iterate(args[0]).toList();
          final reverse = kwargs['reverse'] == true;
          final key = kwargs['key'];
          items = _sortValues(items, key, reverse);
          return PyList(items);
        });
      case 'int':
        return PyBuiltin('int', (args, kwargs) => _toInt(args[0]));
      case 'str':
        return PyBuiltin('str', (args, kwargs) => _str(args[0]));
      case 'float':
        return PyBuiltin('float', (args, kwargs) => _toFloat(args[0]));
      case 'bool':
        return PyBuiltin('bool', (args, kwargs) => _truthy(args[0]));
      case 'abs':
        return PyBuiltin('abs', (args, kwargs) {
          final v = args[0];
          if (v is int) return v.abs();
          if (v is double) return v.abs();
          throw PyError('abs() ожидает число');
        });
      case 'round':
        return PyBuiltin('round', (args, kwargs) {
          final v = args[0];
          final n = args.length > 1 ? _asInt(args[1]) : 0;
          final r = (v as num).toDouble();
          if (n == 0) return r.round();
          final f = math.pow(10, n);
          return (r * f).round() / f;
        });
      case 'type':
        return PyBuiltin(
            'type', (args, kwargs) => "<class '${_typeRepr(args[0])}'>");
      case 'isinstance':
        return PyBuiltin('isinstance', (args, kwargs) {
          final typeName = _str(args[1]).replaceAll(RegExp(r"[<>class ']"), '');
          return _typeName(args[0]) == typeName;
        });
      case 'list':
        return PyBuiltin('list', (args, kwargs) {
          if (args.isEmpty) return PyList();
          return PyList(_iterate(args[0]).toList());
        });
      case 'tuple':
        return PyBuiltin('tuple', (args, kwargs) {
          if (args.isEmpty) return PyTuple([]);
          return PyTuple(_iterate(args[0]).toList());
        });
      case 'dict':
        return PyBuiltin('dict', (args, kwargs) {
          final d = PyDict();
          for (final e in kwargs.entries) {
            _dictSet(d, e.key, e.value);
          }
          if (args.isNotEmpty && args[0] is PyDict) {
            for (final p in (args[0] as PyDict).entries) {
              _dictSet(d, p[0], p[1]);
            }
          }
          return d;
        });
      case 'set':
        return PyBuiltin('set', (args, kwargs) {
          final s = PySet();
          if (args.isEmpty) return s;
          for (final x in _iterate(args[0])) {
            if (!_setHas(s, x)) s.items.add(x);
          }
          return s;
        });
      case 'enumerate':
        return PyBuiltin('enumerate', (args, kwargs) {
          final start = args.length > 1 ? _asInt(args[1]) : 0;
          final items = _iterate(args[0]).toList();
          return PyList([
            for (var i = 0; i < items.length; i++) PyTuple([start + i, items[i]])
          ]);
        });
      case 'super':
        return PyBuiltin('super', (args, kwargs) {
          final inst = _currentInstance;
          final cls = _currentClass;
          if (inst == null || cls == null) {
            throw PyError('super() можно вызывать только внутри метода класса');
          }
          return PySuper(inst, cls);
        });
      default:
        return null;
    }
  }

  dynamic _minmax(List<dynamic> args, bool isMin, Map<String, dynamic> kwargs) {
    final items = args.length == 1 ? _iterate(args[0]).toList() : args;
    if (items.isEmpty) {
      throw PyError(isMin ? 'min() arg is an empty sequence' : 'max() arg is an empty sequence');
    }
    var best = items.first;
    for (final x in items.skip(1)) {
      final c = _compareArgs(x, best);
      if (isMin ? c < 0 : c > 0) best = x;
    }
    return best;
  }

  int _compareArgs(dynamic a, dynamic b) {
    if (a is num && b is num) return a.compareTo(b);
    if (a is String && b is String) return a.compareTo(b);
    if (a is bool && b is num) return (a ? 1 : 0).compareTo(b);
    if (a is num && b is bool) return a.compareTo(b ? 1 : 0);
    throw PyError('Объекты нельзя сравнить');
  }

  List<dynamic> _sortValues(List<dynamic> items, dynamic key, bool reverse) {
    final decorated = <List<dynamic>>[];
    for (var i = 0; i < items.length; i++) {
      final k = key == null ? items[i] : _callValue(key, [items[i]], {});
      decorated.add([k, i, items[i]]);
    }
    decorated.sort((a, b) {
      final c = _compareArgs(a[0], b[0]);
      if (c != 0) return reverse ? -c : c;
      return (a[1] as int).compareTo(b[1] as int);
    });
    return decorated.map((d) => d[2]).toList();
  }

  // ---- operators ----
  dynamic _binop(String op, dynamic l, dynamic r) {
    switch (op) {
      case '+':
        if (l is num && r is num) {
          if (l is int && r is int) return l + r;
          return l.toDouble() + r.toDouble();
        }
        if (l is String && r is String) return l + r;
        if (l is PyList && r is PyList) return PyList([...l.items, ...r.items]);
        if (l is PyTuple && r is PyTuple) return PyTuple([...l.items, ...r.items]);
        throw PyError('Неподдерживаемое сложение: ${_typeName(l)} + ${_typeName(r)}');
      case '-':
        if (l is int && r is int) return l - r;
        if (l is num && r is num) {
          return l.toDouble() - r.toDouble();
        }
        throw PyError('Неподдерживаемое вычитание');
      case '*':
        if (l is num && r is num) {
          if (l is int && r is int) return l * r;
          return l.toDouble() * r.toDouble();
        }
        if (l is String && r is int) return l * r;
        if (l is int && r is String) return r * l;
        if (l is PyList && r is int) {
          final out = <dynamic>[];
          for (var i = 0; i < r; i++) {
            out.addAll(l.items);
          }
          return PyList(out);
        }
        if (l is int && r is PyList) {
          final out = <dynamic>[];
          for (var i = 0; i < l; i++) {
            out.addAll(r.items);
          }
          return PyList(out);
        }
        throw PyError('Неподдерживаемое умножение');
      case '/':
        if (l is num && r is num) {
          if (r == 0) throw PyError('division by zero');
          return l.toDouble() / r.toDouble();
        }
        throw PyError('Неподдерживаемое деление');
      case '//':
        if (l is num && r is num) {
          if (r == 0) throw PyError('integer division or modulo by zero');
          final q = (l / r).floor();
          if (l is int && r is int) return q;
          return q.toDouble();
        }
        throw PyError('Неподдерживаемое целочисленное деление');
      case '%':
        if (l is num && r is num) {
          if (r == 0) throw PyError('integer division or modulo by zero');
          final a = l.toDouble();
          final b = r.toDouble();
          final m = a - b * (a / b).floor();
          if (l is int && r is int) return m.toInt();
          return m;
        }
        throw PyError('Неподдерживаемый остаток');
      case '**':
        if (l is num && r is num) {
          if (l is int && r is int && r >= 0) {
            var result = 1;
            for (var i = 0; i < r; i++) {
              result *= l;
            }
            return result;
          }
          return math.pow(l.toDouble(), r.toDouble());
        }
        throw PyError('Неподдерживаемая степень');
      default:
        throw PyError('Неизвестный оператор $op');
    }
  }

  bool _compare(String op, dynamic l, dynamic r) {
    switch (op) {
      case '==':
        return _equals(l, r);
      case '!=':
        return !_equals(l, r);
      case '<':
        return _compareArgs(l, r) < 0;
      case '>':
        return _compareArgs(l, r) > 0;
      case '<=':
        return _compareArgs(l, r) <= 0;
      case '>=':
        return _compareArgs(l, r) >= 0;
      case 'in':
        return _contains(r, l);
      case 'not in':
        return !_contains(r, l);
      default:
        throw PyError('Неизвестное сравнение $op');
    }
  }

  bool _equals(dynamic a, dynamic b) {
    if (identical(a, b)) return true;
    if (a is PyNone && b is PyNone) return true;
    if (a is bool || b is bool) {
      final an = a is bool ? (a ? 1 : 0) : a;
      final bn = b is bool ? (b ? 1 : 0) : b;
      if (an is num && bn is num) return an == bn;
    }
    if (a is num && b is num) return a == b;
    if (a is String && b is String) return a == b;
    if (a is PyList && b is PyList) return _listEquals(a.items, b.items);
    if (a is PyTuple && b is PyTuple) return _listEquals(a.items, b.items);
    if (a is PyDict && b is PyDict) {
      if (a.entries.length != b.entries.length) return false;
      for (final e in a.entries) {
        final other = _dictGetRaw(b, e[0]);
        if (other == _noValue || !_equals(e[1], other)) return false;
      }
      return true;
    }
    if (a is PySet && b is PySet) {
      if (a.items.length != b.items.length) return false;
      for (final x in a.items) {
        if (!_setHas(b, x)) return false;
      }
      return true;
    }
    return false;
  }

  bool _listEquals(List<dynamic> a, List<dynamic> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_equals(a[i], b[i])) return false;
    }
    return true;
  }

  bool _contains(dynamic container, dynamic item) {
    if (container is String) {
      if (item is! String) throw PyError('in <string> requires string');
      return container.contains(item);
    }
    if (container is PyDict) {
      return _dictGetRaw(container, item) != _noValue;
    }
    if (container is PySet) return _setHas(container, item);
    if (container is PyList || container is PyTuple || container is PyRange) {
      for (final x in _iterate(container)) {
        if (_equals(x, item)) return true;
      }
      return false;
    }
    throw PyError("'${_typeName(container)}' object is not iterable");
  }

  // ---- containers ----
  dynamic _index(dynamic obj, dynamic idx) {
    if (obj is PyList) return _listIndex(obj.items, idx, 'list');
    if (obj is PyTuple) return _listIndex(obj.items, idx, 'tuple');
    if (obj is String) {
      final runes = obj.runes.toList();
      final i = _normalIndex(_asInt(idx), runes.length);
      return String.fromCharCode(runes[i]);
    }
    if (obj is PyDict) {
      final v = _dictGetRaw(obj, idx);
      if (v == _noValue) throw PyError("Ключ ${_repr(idx)} отсутствует в словаре");
      return v;
    }
    throw PyError("'${_typeName(obj)}' object is not subscriptable");
  }

  static final Object _noValue = Object();

  dynamic _listIndex(List<dynamic> items, dynamic idx, String what) {
    final i = _normalIndex(_asInt(idx), items.length);
    return items[i];
  }

  int _normalIndex(int i, int len) {
    var idx = i;
    if (idx < 0) idx += len;
    if (idx < 0 || idx >= len) {
      throw PyError('list index out of range');
    }
    return idx;
  }

  void _setIndex(dynamic obj, dynamic idx, dynamic value) {
    if (obj is PyList) {
      final i = _normalIndex(_asInt(idx), obj.items.length);
      obj.items[i] = value;
      return;
    }
    if (obj is PyDict) {
      _dictSet(obj, idx, value);
      return;
    }
    throw PyError("'${_typeName(obj)}' object does not support item assignment");
  }

  dynamic _slice(dynamic obj, int? start, int? stop, int? step) {
    final st = step ?? 1;
    if (st == 0) throw PyError('slice step cannot be zero');
    final List<dynamic> items;
    var isString = false;
    List<int>? runes;
    if (obj is PyList) {
      items = obj.items;
    } else if (obj is PyTuple) {
      items = obj.items;
    } else if (obj is String) {
      runes = obj.runes.toList();
      items = runes;
      isString = true;
    } else {
      throw PyError("'${_typeName(obj)}' object is not sliceable");
    }
    final len = items.length;
    int norm(int? v, int def) {
      if (v == null) return def;
      var x = v;
      if (x < 0) x += len;
      return x;
    }

    final result = <dynamic>[];
    if (st > 0) {
      var s = norm(start, 0).clamp(0, len);
      var e = norm(stop, len).clamp(0, len);
      for (var i = s; i < e; i += st) {
        result.add(items[i]);
      }
    } else {
      var s = start == null ? len - 1 : norm(start, len - 1);
      if (s > len - 1) s = len - 1;
      var e = stop == null ? -1 : norm(stop, -1);
      if (e < -1) e = -1;
      for (var i = s; i > e; i += st) {
        if (i >= 0 && i < len) result.add(items[i]);
      }
    }
    if (isString) {
      return String.fromCharCodes(result.cast<int>());
    }
    if (obj is PyTuple) return PyTuple(result);
    return PyList(result);
  }

  int _len(dynamic v) {
    if (v is String) return v.runes.length;
    if (v is PyList) return v.items.length;
    if (v is PyTuple) return v.items.length;
    if (v is PyDict) return v.entries.length;
    if (v is PySet) return v.items.length;
    if (v is PyRange) return v.toList().length;
    if (v is PyInstance) {
      final m = _findMethod(v.cls, '__len__');
      if (m != null) return _asInt(_invokeFunction(m, [v], {}));
    }
    throw PyError("object of type '${_typeName(v)}' has no len()");
  }

  List<dynamic> _iterate(dynamic v) {
    if (v is PyList) return List<dynamic>.from(v.items);
    if (v is PyTuple) return List<dynamic>.from(v.items);
    if (v is PySet) return List<dynamic>.from(v.items);
    if (v is PyRange) return v.toList();
    if (v is PyDict) return v.entries.map((e) => e[0]).toList();
    if (v is String) {
      return v.runes.map((r) => String.fromCharCode(r)).toList();
    }
    throw PyError("'${_typeName(v)}' object is not iterable");
  }

  void _dictSet(PyDict d, dynamic key, dynamic value) {
    for (final e in d.entries) {
      if (_equals(e[0], key)) {
        e[1] = value;
        return;
      }
    }
    d.entries.add([key, value]);
  }

  dynamic _dictGetRaw(PyDict d, dynamic key) {
    for (final e in d.entries) {
      if (_equals(e[0], key)) return e[1];
    }
    return _noValue;
  }

  bool _setHas(PySet s, dynamic item) {
    for (final x in s.items) {
      if (_equals(x, item)) return true;
    }
    return false;
  }

  // ---- lenient typed conversions ----
  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is double && v == v.roundToDouble()) return v.toInt();
    if (v is bool) return v ? 1 : 0;
    throw PyError('Ожидалось целое число, получено ${_typeName(v)}');
  }

  dynamic _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.truncate();
    if (v is bool) return v ? 1 : 0;
    if (v is String) {
      final t = v.trim();
      final parsed = int.tryParse(t);
      if (parsed != null) return parsed;
      final d = double.tryParse(t);
      if (d != null) return d.truncate();
      throw PyError("invalid literal for int() with base 10: '$v'");
    }
    throw PyError('int() не поддерживает ${_typeName(v)}');
  }

  dynamic _toFloat(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is bool) return v ? 1.0 : 0.0;
    if (v is String) {
      final d = double.tryParse(v.trim());
      if (d != null) return d;
      throw PyError("could not convert string to float: '$v'");
    }
    throw PyError('float() не поддерживает ${_typeName(v)}');
  }

  // ---- string representation ----
  bool _truthy(dynamic v) {
    if (v is bool) return v;
    if (v is PyNone) return false;
    if (v is int) return v != 0;
    if (v is double) return v != 0;
    if (v is String) return v.isNotEmpty;
    if (v is PyList) return v.items.isNotEmpty;
    if (v is PyTuple) return v.items.isNotEmpty;
    if (v is PyDict) return v.entries.isNotEmpty;
    if (v is PySet) return v.items.isNotEmpty;
    if (v is PyRange) return v.toList().isNotEmpty;
    return true;
  }

  String _typeRepr(dynamic v) {
    if (v is PyInstance) return '__main__.${v.cls.name}';
    if (v is PyClass) return 'type';
    return _typeName(v);
  }

  String _typeName(dynamic v) {    if (v is bool) return 'bool';    if (v is int) return 'int';
    if (v is double) return 'float';
    if (v is String) return 'str';
    if (v is PyNone) return 'NoneType';
    if (v is PyList) return 'list';
    if (v is PyTuple) return 'tuple';
    if (v is PyDict) return 'dict';
    if (v is PySet) return 'set';
    if (v is PyRange) return 'range';
    if (v is PyInstance) return v.cls.name;
    if (v is PyClass) return 'type';
    if (v is PyFunction || v is PyBuiltin || v is PyBoundBuiltin) return 'function';
    if (v is PyNamespace) return 'module';
    if (v is PyResponse) return 'Response';
    return 'object';
  }

  String _str(dynamic v) {
    if (v is String) return v;
    if (v is bool) return v ? 'True' : 'False';
    if (v is PyNone) return 'None';
    if (v is int) return v.toString();
    if (v is double) return _floatStr(v);
    if (v is PyInstance) {
      final m = _findMethod(v.cls, '__str__');
      if (m != null) return _str(_invokeFunction(m, [v], {}));
    }
    return _repr(v);
  }

  String _floatStr(double v) {
    if (v.isNaN) return 'nan';
    if (v.isInfinite) return v > 0 ? 'inf' : '-inf';
    return v.toString();
  }

  String _repr(dynamic v) {
    if (v is String) return _quote(v);
    if (v is PyInstance) {
      final r = _findMethod(v.cls, '__repr__');
      if (r != null) return _str(_invokeFunction(r, [v], {}));
      final s = _findMethod(v.cls, '__str__');
      if (s != null) return _str(_invokeFunction(s, [v], {}));
      return '<__main__.${v.cls.name} object>';
    }
    if (v is PyList) {
      return '[${v.items.map(_repr).join(', ')}]';
    }
    if (v is PyTuple) {
      if (v.items.length == 1) return '(${_repr(v.items[0])},)';
      return '(${v.items.map(_repr).join(', ')})';
    }
    if (v is PyDict) {
      return '{${v.entries.map((e) => '${_repr(e[0])}: ${_repr(e[1])}').join(', ')}}';
    }
    if (v is PySet) {
      return '{${v.items.map(_repr).join(', ')}}';
    }
    if (v is PyRange) {
      if (v.step == 1) return 'range(${v.start}, ${v.stop})';
      return 'range(${v.start}, ${v.stop}, ${v.step})';
    }
    if (v is PyResponse) return '<Response [${v.statusCode}]>';
    return _str(v);
  }

  String _quote(String s) {
    final quote = s.contains("'") && !s.contains('"') ? '"' : "'";
    final buf = StringBuffer(quote);
    for (final rune in s.runes) {
      final ch = String.fromCharCode(rune);
      if (ch == '\\') {
        buf.write('\\\\');
      } else if (ch == quote) {
        buf.write('\\$ch');
      } else if (ch == '\n') {
        buf.write('\\n');
      } else if (ch == '\t') {
        buf.write('\\t');
      } else {
        buf.write(ch);
      }
    }
    buf.write(quote);
    return buf.toString();
  }

  String _formatValue(dynamic v, String? spec) {
    if (spec == null || spec.isEmpty) return _str(v);
    final m = RegExp(r'^\.(\d+)f$').firstMatch(spec);
    if (m != null && v is num) {
      return v.toDouble().toStringAsFixed(int.parse(m.group(1)!));
    }
    if (spec == 'd' && v is int) return v.toString();
    if (spec == 's') return _str(v);
    return _str(v);
  }

  // ---- methods ----
  PyBuiltin? _stringMethod(String s, String name) {
    switch (name) {
      case 'capitalize':
        return PyBuiltin('capitalize', (args, kwargs) {
          if (s.isEmpty) return s;
          return s[0].toUpperCase() + s.substring(1).toLowerCase();
        });
      case 'lower':
        return PyBuiltin('lower', (args, kwargs) => s.toLowerCase());
      case 'upper':
        return PyBuiltin('upper', (args, kwargs) => s.toUpperCase());
      case 'strip':
        return PyBuiltin('strip', (args, kwargs) {
          if (args.isNotEmpty) {
            var t = s;
            final chars = _str(args[0]);
            while (t.isNotEmpty && chars.contains(t[0])) {
              t = t.substring(1);
            }
            while (t.isNotEmpty && chars.contains(t[t.length - 1])) {
              t = t.substring(0, t.length - 1);
            }
            return t;
          }
          return s.trim();
        });
      case 'split':
        return PyBuiltin('split', (args, kwargs) {
          if (args.isEmpty) {
            return PyList(s.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList());
          }
          return PyList(s.split(_str(args[0])));
        });
      case 'join':
        return PyBuiltin('join', (args, kwargs) {
          final parts = _iterate(args[0]).map(_str).join(s);
          return parts;
        });
      case 'count':
        return PyBuiltin('count', (args, kwargs) {
          final sub = _str(args[0]);
          if (sub.isEmpty) return s.length + 1;
          var count = 0;
          var idx = 0;
          while (true) {
            final found = s.indexOf(sub, idx);
            if (found < 0) break;
            count++;
            idx = found + sub.length;
          }
          return count;
        });
      case 'find':
        return PyBuiltin('find', (args, kwargs) => s.indexOf(_str(args[0])));
      case 'replace':
        return PyBuiltin('replace', (args, kwargs) =>
            s.replaceAll(_str(args[0]), _str(args[1])));
      case 'format':
        return PyBuiltin('format', (args, kwargs) {
          var i = 0;
          return s.replaceAllMapped(RegExp(r'\{\}'), (m) => _str(args[i++]));
        });
      case 'startswith':
        return PyBuiltin('startswith', (args, kwargs) => s.startsWith(_str(args[0])));
      case 'endswith':
        return PyBuiltin('endswith', (args, kwargs) => s.endsWith(_str(args[0])));
      default:
        return null;
    }
  }

  PyBuiltin? _listMethod(PyList list, String name) {
    switch (name) {
      case 'append':
        return PyBuiltin('append', (args, kwargs) {
          list.items.add(args[0]);
          return pyNone;
        });
      case 'insert':
        return PyBuiltin('insert', (args, kwargs) {
          var i = _asInt(args[0]);
          if (i < 0) i += list.items.length;
          i = i.clamp(0, list.items.length);
          list.items.insert(i, args[1]);
          return pyNone;
        });
      case 'remove':
        return PyBuiltin('remove', (args, kwargs) {
          for (var i = 0; i < list.items.length; i++) {
            if (_equals(list.items[i], args[0])) {
              list.items.removeAt(i);
              return pyNone;
            }
          }
          throw PyError('list.remove(x): x not in list');
        });
      case 'pop':
        return PyBuiltin('pop', (args, kwargs) {
          final i = args.isEmpty ? list.items.length - 1 : _asInt(args[0]);
          final idx = _normalIndex(i, list.items.length);
          return list.items.removeAt(idx);
        });
      case 'sort':
        return PyBuiltin('sort', (args, kwargs) {
          final reverse = kwargs['reverse'] == true;
          final key = kwargs['key'];
          final sorted = _sortValues(list.items, key, reverse);
          list.items
            ..clear()
            ..addAll(sorted);
          return pyNone;
        });
      case 'count':
        return PyBuiltin('count', (args, kwargs) {
          var c = 0;
          for (final x in list.items) {
            if (_equals(x, args[0])) c++;
          }
          return c;
        });
      case 'index':
        return PyBuiltin('index', (args, kwargs) {
          for (var i = 0; i < list.items.length; i++) {
            if (_equals(list.items[i], args[0])) return i;
          }
          throw PyError('${_repr(args[0])} is not in list');
        });
      case 'extend':
        return PyBuiltin('extend', (args, kwargs) {
          list.items.addAll(_iterate(args[0]));
          return pyNone;
        });
      default:
        return null;
    }
  }

  PyBuiltin? _dictMethod(PyDict d, String name) {
    switch (name) {
      case 'get':
        return PyBuiltin('get', (args, kwargs) {
          final v = _dictGetRaw(d, args[0]);
          if (v == _noValue) return args.length > 1 ? args[1] : pyNone;
          return v;
        });
      case 'keys':
        return PyBuiltin('keys', (args, kwargs) => PyList(d.entries.map((e) => e[0]).toList()));
      case 'values':
        return PyBuiltin(
            'values', (args, kwargs) => PyList(d.entries.map((e) => e[1]).toList()));
      case 'items':
        return PyBuiltin('items', (args, kwargs) =>
            PyList(d.entries.map((e) => PyTuple([e[0], e[1]])).toList()));
      case 'pop':
        return PyBuiltin('pop', (args, kwargs) {
          for (var i = 0; i < d.entries.length; i++) {
            if (_equals(d.entries[i][0], args[0])) {
              final v = d.entries[i][1];
              d.entries.removeAt(i);
              return v;
            }
          }
          return args.length > 1 ? args[1] : pyNone;
        });
      default:
        return null;
    }
  }

  PyBuiltin? _setMethod(PySet s, String name) {
    switch (name) {
      case 'add':
        return PyBuiltin('add', (args, kwargs) {
          if (!_setHas(s, args[0])) s.items.add(args[0]);
          return pyNone;
        });
      case 'remove':
        return PyBuiltin('remove', (args, kwargs) {
          for (var i = 0; i < s.items.length; i++) {
            if (_equals(s.items[i], args[0])) {
              s.items.removeAt(i);
              return pyNone;
            }
          }
          throw PyError('${_repr(args[0])} not in set');
        });
      case 'discard':
        return PyBuiltin('discard', (args, kwargs) {
          for (var i = 0; i < s.items.length; i++) {
            if (_equals(s.items[i], args[0])) {
              s.items.removeAt(i);
              return pyNone;
            }
          }
          return pyNone;
        });
      default:
        return null;
    }
  }

  PyBuiltin? _tupleMethod(PyTuple t, String name) {
    switch (name) {
      case 'count':
        return PyBuiltin('count', (args, kwargs) {
          var c = 0;
          for (final x in t.items) {
            if (_equals(x, args[0])) c++;
          }
          return c;
        });
      case 'index':
        return PyBuiltin('index', (args, kwargs) {
          for (var i = 0; i < t.items.length; i++) {
            if (_equals(t.items[i], args[0])) return i;
          }
          throw PyError('tuple.index(x): x not in tuple');
        });
      default:
        return null;
    }
  }

  // ---- modules ----
  PyNamespace _importModule(String name) {
    final base = name.split('.').first;
    if (_modules.containsKey(base)) return _modules[base]!;
    late PyNamespace ns;
    switch (base) {
      case 'math':
        ns = PyNamespace('math', {
          'pi': math.pi,
          'e': math.e,
          'sqrt': PyBuiltin('sqrt', (a, k) => math.sqrt((a[0] as num).toDouble())),
          'ceil': PyBuiltin('ceil', (a, k) => (a[0] as num).ceil()),
          'floor': PyBuiltin('floor', (a, k) => (a[0] as num).floor()),
          'pow': PyBuiltin('pow', (a, k) =>
              math.pow((a[0] as num).toDouble(), (a[1] as num).toDouble())),
          'fabs': PyBuiltin('fabs', (a, k) => (a[0] as num).abs().toDouble()),
        });
        break;
      case 'random':
        ns = PyNamespace('random', {
          'seed': PyBuiltin('seed', (a, k) {
            _rng = a.isEmpty ? math.Random() : math.Random(_asInt(a[0]));
            return pyNone;
          }),
          'choice': PyBuiltin('choice', (a, k) {
            final items = _iterate(a[0]);
            if (items.isEmpty) throw PyError('Cannot choose from an empty sequence');
            return items[_rng.nextInt(items.length)];
          }),
          'randint': PyBuiltin('randint', (a, k) {
            final lo = _asInt(a[0]);
            final hi = _asInt(a[1]);
            return lo + _rng.nextInt(hi - lo + 1);
          }),
          'random': PyBuiltin('random', (a, k) => _rng.nextDouble()),
          'uniform': PyBuiltin('uniform', (a, k) {
            final lo = (a[0] as num).toDouble();
            final hi = (a[1] as num).toDouble();
            return lo + _rng.nextDouble() * (hi - lo);
          }),
          'shuffle': PyBuiltin('shuffle', (a, k) {
            final list = a[0] as PyList;
            for (var i = list.items.length - 1; i > 0; i--) {
              final j = _rng.nextInt(i + 1);
              final tmp = list.items[i];
              list.items[i] = list.items[j];
              list.items[j] = tmp;
            }
            return pyNone;
          }),
        });
        break;
      case 'json':
        ns = PyNamespace('json', {
          'loads': PyBuiltin('loads', (a, k) => _pyFromJson(convert.jsonDecode(_str(a[0])))),
          'dumps': PyBuiltin('dumps', (a, k) => _jsonEncodePy(a[0])),
        });
        break;
      case 're':
        ns = PyNamespace('re', {
          'findall': PyBuiltin('findall', (a, k) {
            final re = _MiniRegex(_str(a[0]));
            return PyList(re.findAll(_str(a[1])).map((m) => m.text).toList());
          }),
          'sub': PyBuiltin('sub', (a, k) {
            final re = _MiniRegex(_str(a[0]));
            final repl = _str(a[1]);
            return re.sub(_str(a[2]), repl);
          }),
          'search': PyBuiltin('search', (a, k) {
            final re = _MiniRegex(_str(a[0]));
            final m = re.search(_str(a[1]));
            return m == null ? pyNone : m.text;
          }),
        });
        break;
      case 'requests':
        ns = PyNamespace('requests', {
          'get': PyBuiltin(
              'get', (a, k) => _fakeResponse(_str(a.isEmpty ? '' : a[0]))),
          'post': PyBuiltin(
              'post', (a, k) => _fakeResponse(_str(a.isEmpty ? '' : a[0]))),
          'head': PyBuiltin(
              'head', (a, k) => _fakeResponse(_str(a.isEmpty ? '' : a[0]))),
          'RequestException': 'RequestException',
          'exceptions':
              PyNamespace('exceptions', {'RequestException': 'RequestException'}),
        });
        break;
      default:
        if (_unavailableModules.contains(base)) {
          throw PyError(
              "Модуль '$base' недоступен в этом приложении: сеть и системные "
              'модули (datetime, os, sys, pandas и подобные) работают только на '
              'полноценном Python.');
        }
        throw PyError("No module named '$name'");
    }
    _modules[base] = ns;
    return ns;
  }

  static const _unavailableModules = <String>{
    'datetime',
    'os',
    'sys',
    'pandas',
    'socket',
    'subprocess',
    'time',
    'requests_html',
    'bs4',
    'selenium',
  };

  static const _cannedData = <String, Map<String, dynamic>>{
    'rates': {
      'base': 'USD',
      'date': '2026-01-15',
      'rates': {'RUB': 92.5, 'EUR': 0.92, 'GBP': 0.79},
    },
    'search': {
      'results': [
        {'q': 'python'}
      ],
      'total': 1,
    },
    'generate': {
      'choices': [
        {'content': 'Привет, друг!'}
      ],
      'model': 'chat-mini',
    },
  };

  PyResponse _fakeResponse(String url) {
    final u = url.toLowerCase();
    Map<String, dynamic> payload = const {'status': 'ok'};
    if (u.contains('generate') || u.contains('chat') || u.contains('complet')) {
      payload = _cannedData['generate']!;
    } else if (u.contains('rate')) {
      payload = _cannedData['rates']!;
    } else if (u.contains('search')) {
      payload = _cannedData['search']!;
    }
    final headers = PyDict([
      ['Content-Type', 'application/json; charset=utf-8'],
      ['Server', 'fake-api'],
    ]);
    return PyResponse(200, 'OK', _pyFromJson(payload), headers, url);
  }

  dynamic _pyFromJson(dynamic v) {
    if (v is List) return PyList(v.map(_pyFromJson).toList());
    if (v is Map) {
      final d = PyDict();
      v.forEach((k, val) => d.entries.add([k.toString(), _pyFromJson(val)]));
      return d;
    }
    if (v is bool) return v;
    if (v is num) return v;
    if (v is String) return v;
    return pyNone;
  }

  String _jsonEncodePy(dynamic v) {
    if (v is PyNone) return 'null';
    if (v is bool) return v ? 'true' : 'false';
    if (v is int) return v.toString();
    if (v is double) return v.toString();
    if (v is String) return _jsonString(v);
    if (v is PyList) {
      return '[${v.items.map(_jsonEncodePy).join(', ')}]';
    }
    if (v is PyTuple) {
      return '[${v.items.map(_jsonEncodePy).join(', ')}]';
    }
    if (v is PyDict) {
      return '{${v.entries.map((e) => '${_jsonString(_str(e[0]))}: ${_jsonEncodePy(e[1])}').join(', ')}}';
    }
    throw PyError('Object of type ${_typeName(v)} is not JSON serializable');
  }

  String _jsonString(String s) {
    final buf = StringBuffer('"');
    for (final rune in s.runes) {
      final ch = String.fromCharCode(rune);
      switch (ch) {
        case '"':
          buf.write('\\"');
          break;
        case '\\':
          buf.write('\\\\');
          break;
        case '\n':
          buf.write('\\n');
          break;
        case '\t':
          buf.write('\\t');
          break;
        case '\r':
          buf.write('\\r');
          break;
        default:
          if (rune < 0x20) {
            buf.write('\\u${rune.toRadixString(16).padLeft(4, '0')}');
          } else {
            buf.write(ch);
          }
      }
    }
    buf.write('"');
    return buf.toString();
  }
}

// ---------------------------------------------------------------------------
// Mini regex engine (covers \d \w \s . + * ? [] [^] | ^ $ )
// ---------------------------------------------------------------------------

class _Match {
  final int start;
  final int end;
  final String text;
  _Match(this.start, this.end, this.text);
}

class _RNode {
  final String kind; // char, class, any, start, end, group
  final List<dynamic> value;
  int min = 1;
  int max = 1;
  List<List<_RNode>> alts = [];
  _RNode(this.kind, [this.value = const []]);
}

class _MiniRegex {
  final String pattern;
  late List<List<_RNode>> _alts;

  _MiniRegex(this.pattern) {
    _alts = _parseAlternatives(pattern, 0, pattern.length);
  }

  static List<List<_RNode>> _parseAlternatives(String p, int start, int end) {
    final alts = <List<_RNode>>[];
    var seq = <_RNode>[];
    var i = start;
    while (i < end) {
      if (p[i] == '|') {
        alts.add(seq);
        seq = [];
        i++;
        continue;
      }
      final node = _parseAtom(p, i, end);
      i = node[0] as int;
      var n = node[1] as _RNode;
      if (i < end && (p[i] == '+' || p[i] == '*' || p[i] == '?')) {
        if (p[i] == '+') {
          n.min = 1;
          n.max = 999999;
        } else if (p[i] == '*') {
          n.min = 0;
          n.max = 999999;
        } else {
          n.min = 0;
          n.max = 1;
        }
        i++;
      }
      seq.add(n);
    }
    alts.add(seq);
    return alts;
  }

  static List<dynamic> _parseAtom(String p, int i, int end) {
    final c = p[i];
    if (c == '\\' && i + 1 < end) {
      final e = p[i + 1];
      switch (e) {
        case 'd':
          return [i + 2, _RNode('class', ['digit'])];
        case 'D':
          return [i + 2, _RNode('class', ['notdigit'])];
        case 'w':
          return [i + 2, _RNode('class', ['word'])];
        case 'W':
          return [i + 2, _RNode('class', ['notword'])];
        case 's':
          return [i + 2, _RNode('class', ['space'])];
        case 'S':
          return [i + 2, _RNode('class', ['notspace'])];
        default:
          return [i + 2, _RNode('char', [e])];
      }
    }
    if (c == '.') return [i + 1, _RNode('any')];
    if (c == '^') return [i + 1, _RNode('start')];
    if (c == r'$') return [i + 1, _RNode('end')];
    if (c == '[') {
      var j = i + 1;
      var negate = false;
      if (j < end && p[j] == '^') {
        negate = true;
        j++;
      }
      final items = <String>[];
      while (j < end && p[j] != ']') {
        if (p[j] == '\\' && j + 1 < end) {
          final e = p[j + 1];
          if (e == 'd') {
            items.add('digit');
          } else if (e == 'w') {
            items.add('word');
          } else if (e == 's') {
            items.add('space');
          } else {
            items.add(e);
          }
          j += 2;
        } else if (j + 2 < end && p[j + 1] == '-' && p[j + 2] != ']') {
          items.add('range:${p[j]}-${p[j + 2]}');
          j += 3;
        } else {
          items.add(p[j]);
          j++;
        }
      }
      final node = _RNode('class', items);
      if (negate) node.value.add('__negate__');
      return [j + 1, node];
    }
    if (c == '(') {
      // find matching )
      var depth = 1;
      var j = i + 1;
      while (j < end && depth > 0) {
        if (p[j] == '(') depth++;
        if (p[j] == ')') depth--;
        if (depth == 0) break;
        j++;
      }
      final sub = _parseAlternatives(p, i + 1, j);
      final node = _RNode('group');
      node.alts = sub;
      return [j + 1, node];
    }
    return [i + 1, _RNode('char', [c])];
  }

  bool _classMatch(_RNode node, String ch) {
    var negate = false;
    final items = node.value;
    for (final it in items) {
      if (it == '__negate__') negate = true;
    }
    var matched = false;
    for (final it in items) {
      if (it == '__negate__') continue;
      if (it == 'digit') {
        if (ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57) matched = true;
      } else if (it == 'notdigit') {
        if (!(ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57)) matched = true;
      } else if (it == 'word') {
        if (RegExp(r'[A-Za-z0-9_]').hasMatch(ch)) matched = true;
      } else if (it == 'notword') {
        if (!RegExp(r'[A-Za-z0-9_]').hasMatch(ch)) matched = true;
      } else if (it == 'space') {
        if (RegExp(r'\s').hasMatch(ch)) matched = true;
      } else if (it == 'notspace') {
        if (!RegExp(r'\s').hasMatch(ch)) matched = true;
      } else if (it is String && it.startsWith('range:')) {
        final parts = it.substring(6).split('-');
        final lo = parts[0].codeUnitAt(0);
        final hi = parts[1].codeUnitAt(0);
        final cc = ch.codeUnitAt(0);
        if (cc >= lo && cc <= hi) matched = true;
      } else if (it == ch) {
        matched = true;
      }
    }
    return negate ? !matched : matched;
  }

  List<dynamic>? _matchNodes(List<_RNode> nodes, String s, int pos, int nodeIdx) {
    if (nodeIdx >= nodes.length) return [pos, <String>[]];
    final node = nodes[nodeIdx];
    final results = <List<dynamic>>[];
    if (node.kind == 'start') {
      if (pos == 0) {
        final r = _matchNodes(nodes, s, pos, nodeIdx + 1);
        if (r != null) results.add(r);
      }
      return results.isEmpty ? null : results.first;
    }
    if (node.kind == 'end') {
      if (pos == s.length) {
        final r = _matchNodes(nodes, s, pos, nodeIdx + 1);
        if (r != null) results.add(r);
      }
      return results.isEmpty ? null : results.first;
    }
    final counts = <int>[];
    var p = pos;
    while (counts.length < node.max) {
      final next = _matchOne(node, s, p);
      if (next == null) break;
      counts.add(next);
      p = next;
    }
    for (var c = counts.length; c >= node.min; c--) {
      final at = c == 0 ? pos : counts[c - 1];
      final r = _matchNodes(nodes, s, at, nodeIdx + 1);
      if (r != null) {
        final groups = (r[1] as List).cast<String>();
        return [r[0], groups];
      }
    }
    return null;
  }

  int? _matchOne(_RNode node, String s, int pos) {
    if (pos >= s.length) return null;
    final ch = s[pos];
    if (node.kind == 'char') return ch == node.value[0] ? pos + 1 : null;
    if (node.kind == 'any') return pos + 1;
    if (node.kind == 'class') return _classMatch(node, ch) ? pos + 1 : null;
    if (node.kind == 'group') {
      for (final alt in node.alts) {
        final r = _matchNodes(alt, s, pos, 0);
        if (r != null) return r[0] as int;
      }
      return null;
    }
    return null;
  }

  _Match? _matchAt(String s, int start) {
    for (final alt in _alts) {
      final r = _matchNodes(alt, s, start, 0);
      if (r != null) {
        final end = r[0] as int;
        return _Match(start, end, s.substring(start, end));
      }
    }
    return null;
  }

  List<_Match> findAll(String s) {
    final matches = <_Match>[];
    var pos = 0;
    while (pos <= s.length) {
      final m = _matchAt(s, pos);
      if (m == null) {
        pos++;
        continue;
      }
      matches.add(m);
      pos = m.end > m.start ? m.end : m.start + 1;
    }
    return matches;
  }

  _Match? search(String s) {
    for (var i = 0; i <= s.length; i++) {
      final m = _matchAt(s, i);
      if (m != null) return m;
    }
    return null;
  }

  String sub(String s, String repl) {
    final matches = findAll(s);
    final buf = StringBuffer();
    var pos = 0;
    for (final m in matches) {
      buf.write(s.substring(pos, m.start));
      buf.write(repl);
      pos = m.end;
    }
    buf.write(s.substring(pos));
    return buf.toString();
  }
}
