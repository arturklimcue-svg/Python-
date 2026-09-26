#!/usr/bin/env python3
"""Добавляет в AndroidManifest всё, что нужно для запуска команд в Termux.

Каталог android/ не хранится в репозитории — его генерирует `flutter create`
в CI, поэтому недостающие записи манифеста дописываются сюда.

Зачем:
  * com.termux.permission.RUN_COMMAND — без этого Android не даст слать
    intent в com.termux.app.RunCommandService, а значит Termux не выполнит
    команды установки/запуска opencode;
  * <queries> — чтобы приложение видело пакет com.termux (Android 11+).

Скрипт идемпотентен: повторный запуск ничего не дублирует.
"""

import sys
from pathlib import Path

MANIFEST = Path("android/app/src/main/AndroidManifest.xml")

PERMISSION = (
    '  <uses-permission android:name="com.termux.permission.RUN_COMMAND" />\n'
    "\n"
    '  <queries>\n'
    '    <package android:name="com.termux" />\n'
    "  </queries>\n"
)


def main() -> int:
    if not MANIFEST.exists():
        print(f"!! {MANIFEST} не найден — сначала выполни flutter create", file=sys.stderr)
        return 1

    text = MANIFEST.read_text(encoding="utf-8")
    if "com.termux.permission.RUN_COMMAND" in text:
        print("Манифест уже пропатчен — пропускаю")
        return 0

    if "</manifest>" not in text:
        print("!! нет закрывающего </manifest>", file=sys.stderr)
        return 1

    MANIFEST.write_text(
        text.replace("</manifest>", PERMISSION + "</manifest>"), encoding="utf-8"
    )
    print("Манифест пропатчен: RUN_COMMAND + queries для com.termux")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
