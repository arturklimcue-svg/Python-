import 'package:flutter/services.dart';

/// Доступ к настоящему Python (CPython) внутри Android-приложения.
///
/// Канал регистрируется нативным плагином. Если плагин недоступен
/// (например, тесты на хосте), методы бросят [MissingPluginException] —
/// вызывающий код должен уметь откатиться на встроенный интерпретатор.
class KodikPython {
  KodikPython._();

  static const MethodChannel channel = MethodChannel('kodik/python');

  /// Запущен ли настоящий интерпретатор.
  static Future<bool> available() async {
    try {
      return await channel.invokeMethod<bool>('available') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Выполняет [code], отдавая строки [stdin] в `input()`.
  /// Возвращает JSON-строку с полями ok/stdout/error/inputsMissing.
  static Future<String?> run(String code, List<String> stdin) {
    return channel.invokeMethod<String>('run', {
      'code': code,
      'stdin': stdin,
    });
  }
}
