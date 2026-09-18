import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:kodik_python/kodik_python.dart';

import 'python_interpreter.dart';

/// Запуск Python-кода для приложения.
///
/// На Android используется настоящий CPython (плагин `kodik_python`).
/// Если он недоступен — например, в тестах или при сбое инициализации —
/// автоматически берётся встроенный учебный интерпретатор, чтобы приложение
/// продолжало работать.
class PythonRuntime {
  PythonRuntime._();

  static bool? _native;

  /// Доступен ли настоящий Python. Значение кэшируется.
  static Future<bool> get usesNativePython async {
    final cached = _native;
    if (cached != null) return cached;
    if (kIsWeb || !Platform.isAndroid) return _native = false;
    return _native = await KodikPython.available();
  }

  static Future<PyRunResult> run(String code, {String stdin = ''}) async {
    if (await usesNativePython) {
      try {
        final raw = await KodikPython.run(code, _splitStdin(stdin));
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

/// Возвращает «хвост» нового вывода, который пользователь ещё не видел.
///
/// Программы с `input()` выполняются заново со всеми накопленными строками,
/// поэтому обычный вывод повторяет всё сначала. Если новый вывод начинается
/// с предыдущего — показываем только добавленные строки, и консоль растёт,
/// как настоящая. Если вывод изменился с начала (например, `random`),
/// отдаём весь новый вывод целиком.
String diffOutputTail(String previous, String next) {
  if (previous.isEmpty) return next;
  if (next.startsWith(previous)) return next.substring(previous.length);
  return next;
}
