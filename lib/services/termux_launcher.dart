import 'package:flutter/services.dart';

/// Канал, который регистрирует нативная часть `android_intent_plus`.
///
/// Обращаемся к нему напрямую, а не через класс `AndroidIntent`, потому что
/// тот внутри возвращается молча, если `LocalPlatform().isAndroid == false` —
/// на CI (ubuntu) это так, и канал бы вообще не вызывался. Формат аргументов
/// ниже повторяет `_buildArguments()` из android_intent_plus.
const MethodChannel _intentChannel =
    MethodChannel('dev.fluttercommunity.plus/android_intent');

/// Открывает Termux на устройстве — в нём живёт AI-сервер.
///
/// Приложение ходит к `opencode serve`, который слушает `127.0.0.1:4096`.
/// Сервер ставится и запускается прямо в Termux через
/// `com.termux.app.RunCommandService`: приложение не копирует файлы, а
/// передаёт скрипт в stdin, Termux выполняет его в видимой сессии.
///
/// Для RunCommandService нужны два разовых разрешения, которые выдаёт сам
/// пользователь (см. [TermuxPrerequisites]):
///   * в Android-настройках приложения — «Запускать команды в Termux»
///     (`com.termux.permission.RUN_COMMAND`);
///   * в Termux — `allow-external-apps = true` в `~/.termux/termux.properties`.
class TermuxLauncher {
  TermuxLauncher._();

  static const String androidPackage = 'com.termux';
  static const String termuxActivity = 'com.termux.app.TermuxActivity';
  static const String runCommandService = 'com.termux.app.RunCommandService';
  static const String runCommandAction = 'com.termux.RUN_COMMAND';

  /// Шелл Termux. Путь начинается с `$PREFIX/`, Termux разворачивает его сам.
  static const String bashPath = r'$PREFIX/bin/bash';

  /// Открывает окно Termux (без выполнения команд).
  static Future<LaunchResult> open() async {
    try {
      await _intentChannel.invokeMethod<void>('launch', {
        'action': 'android.intent.action.MAIN',
        'category': 'android.intent.category.LAUNCHER',
        'package': androidPackage,
        'componentName': termuxActivity,
      });
      return LaunchResult.ok();
    } on PlatformException catch (e) {
      return LaunchResult.error(_describePlatformError(e));
    } on MissingPluginException {
      return LaunchResult.error(
        'Плагин android_intent_plus не подключён. Пересобери приложение.',
      );
    }
  }

  /// Открывает Termux и выполняет в нём скрипт установки и запуска opencode.
  ///
  /// Скрипт уходит в stdin, поэтому не зависит от экранирования кавычек и не
  /// упирается в лимит длины аргументов. Сессия Termux видимая — пользователь
  /// видит все выполняемые команды и вывод установки.
  static Future<LaunchResult> openAndRunBootstrap() async {
    final opened = await open();
    if (opened.status != 'ok') return opened;
    return runBootstrap();
  }

  /// Просит Termux выполнить [bootstrapScript] в новой видимой сессии.
  static Future<LaunchResult> runBootstrap() async {
    try {
      await _intentChannel.invokeMethod<void>('sendService', {
        'action': runCommandAction,
        'package': androidPackage,
        'componentName': runCommandService,
        'arrayArguments': const {
          'com.termux.RUN_COMMAND_ARGUMENTS': <String>[],
        },
        'arguments': {
          'com.termux.RUN_COMMAND_PATH': bashPath,
          'com.termux.RUN_COMMAND_WORKDIR': r'$HOME',
          'com.termux.RUN_COMMAND_STDIN': bootstrapScript,
          'com.termux.RUN_COMMAND_BACKGROUND': false,
          'com.termux.RUN_COMMAND_SESSION_ACTION': '0',
          'com.termux.RUN_COMMAND_COMMAND_LABEL': 'КодиК: запуск opencode',
          'com.termux.RUN_COMMAND_COMMAND_DESCRIPTION':
              'Установка opencode и запуск AI-сервера на 127.0.0.1:4096.',
        },
      });
      return LaunchResult.bootstrapSent();
    } on PlatformException catch (e) {
      return LaunchResult.error(_describeRunCommandError(e));
    } on MissingPluginException {
      return LaunchResult.error(
        'Плагин android_intent_plus не подключён. Пересобери приложение.',
      );
    }
  }

  /// Скрипт установки и запуска. Идёт в Termux через stdin, поэтому не
  /// требует экранирования и остаётся читаемым.
  static const String bootstrapScript = r'''
export DEBIAN_FRONTEND=noninteractive
PORT=4096
PREFIX_DIR="${PREFIX:-/data/data/com.termux/files/usr}"
HOME_DIR="${HOME:-/data/data/com.termux/files/home}"
KODIK_DIR="$HOME_DIR/kodik"

say() { printf '\n=== %s ===\n' "$1"; }

say "1/5 Ставлю Node.js (нужен для opencode)"
pkg update -y >/dev/null 2>&1
pkg install -y nodejs-lts >/dev/null 2>&1 || pkg install -y nodejs >/dev/null 2>&1
if ! command -v node >/dev/null 2>&1; then
  echo "!! Не удалось поставить node. Проверь интернет и повтори."
  exit 1
fi
node -v

say "2/5 Ставлю opencode"
if ! command -v opencode >/dev/null 2>&1; then
  npm install -g opencode-ai --unsafe-perm 2>&1 | tail -n 5
fi
if ! command -v opencode >/dev/null 2>&1; then
  echo "!! opencode не установился. Проверь интернет и повтори."
  exit 1
fi
opencode --version

say "3/5 Готовлю ~/kodik"
mkdir -p "$KODIK_DIR"
cat > "$KODIK_DIR/start_server.sh" <<'KODIK_SERVER_EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Запуск/остановка AI-сервера «КодиК» (opencode serve).
PORT="${OPCODE_PORT:-4096}"
case "${1:-start}" in
  start)
    if curl -fsS --max-time 1 -o /dev/null "http://127.0.0.1:${PORT}/global/health"; then
      echo "Сервер уже запущен"; exit 0
    fi
    nohup opencode serve --hostname 127.0.0.1 --port "$PORT" \
      >"$HOME/kodik/server.log" 2>&1 &
    echo $! > "$HOME/kodik/server.pid"
    echo "Запущен opencode serve (PID $!)"
    ;;
  stop)
    [ -f "$HOME/kodik/server.pid" ] && kill "$(cat "$HOME/kodik/server.pid")" 2>/dev/null
    rm -f "$HOME/kodik/server.pid"
    echo "Сервер остановлен"
    ;;
  log)  tail -n 50 -f "$HOME/kodik/server.log" ;;
  *)    echo "Использование: $0 {start|stop|log}"; exit 1 ;;
esac
KODIK_SERVER_EOF
chmod +x "$KODIK_DIR/start_server.sh"

say "4/5 Включаю автозапуск при загрузке телефона"
mkdir -p "$HOME_DIR/.termux/boot"
cat > "$HOME_DIR/.termux/boot/start_kodik_server.sh" <<'KODIK_BOOT_EOF'
#!/data/data/com.termux/files/usr/bin/bash
"$HOME/kodik/start_server.sh" start
KODIK_BOOT_EOF
chmod +x "$HOME_DIR/.termux/boot/start_kodik_server.sh"
echo "Готово: ~/.termux/boot/start_kodik_server.sh"
echo "Чтобы сервер поднимался сам — установи Termux:Boot из F-Droid."

say "5/5 Запускаю AI-сервер на 127.0.0.1:${PORT}"
bash "$KODIK_DIR/start_server.sh" start
sleep 3
if curl -fsS --max-time 2 -o /dev/null "http://127.0.0.1:${PORT}/global/health"; then
  echo "ГОТОВО: сервер отвечает. В приложении жми «Проверить соединение»."
else
  echo "Сервер запущен, но пока не отвечает. Подожди немного и проверь:"
  echo "  tail -n 50 ~/kodik/server.log"
fi
''';

  /// Android в сообщениях отдаёт код, а не текст для человека.
  static String _describePlatformError(PlatformException e) {
    final code = e.code;
    if (code == 'activity_not_found' || code.contains('ActivityNotFound')) {
      return LaunchResult.notInstalled().message;
    }
    if (code == 'SecurityException' || code.contains('Permission')) {
      return TermuxPrerequisites.permissionMissing;
    }
    return 'Не удалось открыть Termux: ${e.message ?? code}';
  }

  static String _describeRunCommandError(PlatformException e) {
    final code = e.code;
    if (code.contains('Permission') ||
        code.contains('SecurityException') ||
        code.contains('not exported')) {
      return TermuxPrerequisites.permissionMissing;
    }
    return 'Termux не выполнил команды.\n'
        '${e.message ?? code}\n\n${TermuxPrerequisites.short}';
  }
}

/// Разовые условия, которые должен включить сам пользователь.
class TermuxPrerequisites {
  TermuxPrerequisites._();

  static const String permissionMissing =
      'Termux не разрешил запуск команд.\n\nЧто сделать один раз:\n'
      '1. Android Настройки → Приложения → КодиК → Разрешения → '
      '«Запускать команды в Termux» — включить.\n'
      '2. В Termux выполнить:\n'
      '   mkdir -p ~/.termux\n'
      '   echo "allow-external-apps = true" >> ~/.termux/termux.properties\n'
      '   затем перезапустить Termux\n'
      '3. Нажать «Открыть Termux» ещё раз.';

  static const String short = 'Разреши «Запускать команды в Termux» в настройках '
      'приложения и выполни в Termux: '
      'echo "allow-external-apps = true" >> ~/.termux/termux.properties';
}

class LaunchResult {
  const LaunchResult(this.status, this.message);

  final String status;
  final String message;

  bool get isOk => status == 'ok' || status == 'bootstrap';

  factory LaunchResult.ok() => const LaunchResult(
        'ok',
        'Termux открыт.\nКоманды на установку opencode сейчас выполняются в '
        'нём — смотри окно Termux.',
      );
  factory LaunchResult.bootstrapSent() => const LaunchResult(
        'bootstrap',
        'Команды отправлены в Termux.\nТам ставятся Node.js и opencode, '
        'затем сервер поднимается на 127.0.0.1:4096. Дождись конца установки '
        'и вернись в приложение.',
      );
  factory LaunchResult.notInstalled() => const LaunchResult(
        'not_installed',
        'Termux не найден. Поставь его из F-Droid (com.termux), '
        'затем нажми кнопку ещё раз.',
      );
  factory LaunchResult.error(String message) => LaunchResult('error', message);

  @override
  String toString() => message;
}
