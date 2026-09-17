#!/usr/bin/env bash
# Добавляет настоящий Python (Chaquopy) в сгенерированный Android-проект.
# Скрипт вызывает CI после `flutter create`, поэтому он работает с шаблоном
# Flutter, а не с закоммиченными файлами платформы.
set -euo pipefail

KTS=android/app/build.gradle.kts
GROOVY=android/app/build.gradle
MAIN=android/app/src/main/kotlin/com/arturklimcue/kodik/MainActivity.kt
PYDIR=android/app/src/main/python

if [ -f "$KTS" ]; then
  LANG_FILE="$KTS"
elif [ -f "$GROOVY" ]; then
  LANG_FILE="$GROOVY"
else
  echo "!! Не найден build.gradle(.kts) приложения"
  find android -maxdepth 4 -type f | sort || true
  exit 1
fi

echo "== Патчу $LANG_FILE =="

python3 - "$LANG_FILE" <<'PY'
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
is_kts = path.endswith(".kts")

if is_kts:
    anchor = 'id("com.android.application")'
    plugin = 'id("com.android.application")\n    id("com.chaquo.python") version "16.1.0"'
    extra = """

android {
    defaultConfig {
        minSdk = 24
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }
}

chaquopy {
    defaultConfig {
        version = "3.11"
    }
}
"""
else:
    anchor = 'id "com.android.application"'
    plugin = 'id "com.android.application"\n    id "com.chaquo.python" version "16.1.0"'
    extra = """

android {
    defaultConfig {
        minSdk 24
        ndk {
            abiFilters "arm64-v8a"
        }
    }
}

chaquopy {
    defaultConfig {
        version = "3.11"
    }
}
"""

if anchor not in text:
    print("!! Не найден якорь:", anchor)
    print(text)
    sys.exit(1)

text = text.replace(anchor, plugin, 1)
text += extra
open(path, "w", encoding="utf-8").write(text)
print("ok:", path)
for line in text.splitlines():
    print("   |", line)
PY

mkdir -p "$PYDIR"
cp -f android_overlay/python/kodik_runtime.py "$PYDIR/kodik_runtime.py"
cp -f android_overlay/python/requests.py "$PYDIR/requests.py"

mkdir -p "$(dirname "$MAIN")"
cp -f android_overlay/MainActivity.kt "$MAIN"

echo "== Python-файлы в приложении =="
find "$PYDIR" -type f -maxdepth 1 -print
echo "== Chaquopy готов =="
