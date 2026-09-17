"""Мост между Flutter и настоящим CPython (Chaquopy).

Модуль запускает код ученика как обычную программу Python и возвращает
результат в виде JSON-строки. Поведение намеренно повторяет встроенный
учебный интерпретатор приложения:

* ``print`` пишет в ``stdout``;
* ``input()`` берёт очередную строку из переданного списка, а если данные
  закончились — возвращает пустую строку и увеличивает счётчик
  ``inputsMissing`` (приложение по нему понимает, что нужен новый ответ);
* ошибки возвращаются последней строкой трассировки.
"""

import io
import json
import sys
import traceback

_UNAVAILABLE = {
    "pandas": "Модуль pandas недоступен в этом приложении. Работа с таблицами "
    "рассматривается позже, на полноценном Python.",
    "numpy": "Модуль numpy недоступен в этом приложении — он слишком большой.",
    "matplotlib": "Модуль matplotlib недоступен: графику в приложении "
    "нарисовать нельзя.",
    "bs4": "Модуль bs4 недоступен в этом приложении.",
    "requests_html": "Модуль requests_html недоступен в этом приложении.",
    "selenium": "Модуль selenium недоступен в этом приложении.",
    "tkinter": "Модуль tkinter недоступен: в приложении нет окон.",
}


class _BlockedLoader:
    def __init__(self, message):
        self._message = message

    def create_module(self, spec):
        return None

    def exec_module(self, module):
        raise ImportError(self._message)


class _BlockedFinder:
    def find_spec(self, fullname, path=None, target=None):
        base = fullname.split(".")[0]
        if base in _UNAVAILABLE:
            import importlib.machinery

            return importlib.machinery.ModuleSpec(
                fullname, _BlockedLoader(_UNAVAILABLE[base])
            )
        return None


def _install_blocker():
    if not any(isinstance(f, _BlockedFinder) for f in sys.meta_path):
        sys.meta_path.insert(0, _BlockedFinder())


class _Stdin:
    def __init__(self, lines):
        self.lines = list(lines)
        self.index = 0

    def readline(self, *args, **kwargs):
        if self.index < len(self.lines):
            value = self.lines[self.index]
            self.index += 1
            return value if value.endswith("\n") else value + "\n"
        return None

    def read(self, *args, **kwargs):
        rest = "".join(self.lines[self.index:])
        self.index = len(self.lines)
        return rest


def run(code, stdin_lines=None):
    """Выполняет код и возвращает JSON с полями ok/stdout/error/inputsMissing."""
    _install_blocker()
    lines = list(stdin_lines or [])
    out = io.StringIO()
    missing = [0]
    stdin_obj = _Stdin(lines)

    def fake_input(prompt=""):
        if prompt:
            out.write(str(prompt))
        line = stdin_obj.readline()
        if line is None:
            missing[0] += 1
            return ""
        return line.rstrip("\n")

    saved = (sys.stdin, sys.stdout, sys.stderr)
    try:
        sys.stdin = stdin_obj
        sys.stdout = out
        sys.stderr = out
        scope = {"__name__": "__main__", "input": fake_input}
        exec(compile(code, "<программа>", "exec"), scope)
        return _result(True, out.getvalue(), "", missing[0])
    except BaseException:  # noqa: BLE001 - ученику нужна любая ошибка
        tb = traceback.format_exc().strip().splitlines()
        message = tb[-1] if tb else "Ошибка выполнения"
        return _result(False, out.getvalue(), message, missing[0])
    finally:
        sys.stdin, sys.stdout, sys.stderr = saved


def _result(ok, stdout, error, inputs_missing):
    return json.dumps(
        {
            "ok": ok,
            "stdout": stdout,
            "error": error,
            "inputsMissing": inputs_missing,
        },
        ensure_ascii=False,
    )
