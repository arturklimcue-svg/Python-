import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import 'python_interpreter.dart';

/// Запуск Python-кода для приложения.
///
/// На Android используется настоящий CPython (Chaquopy). Если он недоступен
/// — например, в тестах или при сбое инициализации — автоматически берётся
/// встроенный учебный интерпретатор, чтобы приложение продолжало работать.
class PythonRuntime {
  PythonRuntime._();

  static const MethodChannel _channel = MethodChannel('kodik/python');
  static bool? _native;

  /// Доступен ли настоящий Python. Значение кэшируется.
  static Future<bool> get usesNativePython async {
    final cached = _native;
    if (cached != null) return cached;
    if (kIsWeb || !Platform.isAndroid) return _native = false;
    try {
      final result = await _channel.invokeMethod<bool>('available');
      return _native = result ?? false;
    } catch (_) {
      return _native = false;
    }
  }

  static Future<PyRunResult> run(String code, {String stdin = ''}) async {
    if (await usesNativePython) {
      try {
        final raw = await _channel.invokeMethod<String>('run', {
          'code': code,
          'stdin': _splitStdin(stdin),
        });
        if (raw != null) {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          return PyRunResult(
            map['ok'] == true,
            (map['stdout'] as String?) ?? '',
            (map['error'] as String?) ?? '',
            inputsMissing: (map['inputsMissing'] as num?)?.toInt() ?? 0,
          );
        }
      } catch (_) {
        // Нативный движок не справился — пробуем встроенный.
      }
    }
    return runPython(code, stdin: stdin);
  }

  /// Пустой stdin → пустой список, хвостовой перевод строки не создаёт
  /// фантомную пустую строку. Аналогично встроенному интерпретатору.
  static List<String> _splitStdin(String stdin) {
    if (stdin.isEmpty) return const [];
    final lines = stdin.split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    return lines;
  }
}
