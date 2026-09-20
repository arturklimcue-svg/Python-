import 'package:flutter/services.dart';

/// Открывает Termux на устройстве — в нём живёт AI-сервер.
///
/// Приложение ходит к `opencode serve`, который слушает `127.0.0.1:4096`.
/// Сам сервер запускается в Termux (другой способ держать `opencode` на
/// телефоне без рута не существует). Эта служба лишь открывает Termux и
/// возвращает результат, чтобы экран мог подсказать пользователю, что делать.
class TermuxLauncher {
  TermuxLauncher._();

  static const String androidPackage = 'com.termux';
  static const String termuxActivity = 'com.termux.app.TermuxActivity';

  /// Открывает Termux (стартовый экран приложения Termux).
  static Future<LaunchResult> open() async {
    try {
      const channel = MethodChannel('plugins.flutter.io/android_intent_plus');
      final resolved = await channel.invokeMethod<bool>('resolve', {
        'package': androidPackage,
        'component': '$androidPackage/$termuxActivity',
      });
      if (resolved != true) return LaunchResult.notInstalled();
      final started =
          await channel.invokeMethod<bool>('startActivity', {
        'package': androidPackage,
        'component': '$androidPackage/$termuxActivity',
      });
      return started == true ? LaunchResult.ok() : LaunchResult.unableToOpen();
    } on MissingPluginException {
      return LaunchResult.error('Не удалось открыть Termux');
    } on PlatformException {
      return LaunchResult.error('Не удалось открыть Termux');
    }
  }
}

class LaunchResult {
  const LaunchResult(this.status, this.message);

  final String status;
  final String message;

  bool get isOk => status == 'ok';

  factory LaunchResult.ok() => const LaunchResult('ok', 'Termux открыт');
  factory LaunchResult.notInstalled() => LaunchResult(
        'not_installed',
        'Termux не установлен. Поставь его из F-Droid '
        '(com.termux), затем нажми «Открыть Termux» ещё раз.',
      );
  factory LaunchResult.unableToOpen() =>
      const LaunchResult('error', 'Не удалось открыть Termux');
  factory LaunchResult.error(String message) => LaunchResult('error', message);

  @override
  String toString() => message;
}
