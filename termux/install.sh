#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

# Полная установка AI-сервера «КодиК» в Termux на этом телефоне.
# Запускать ОДНИМ из двух способов:
#   1. Приложением: Настройки AI -> «Открыть Termux» (кнопка открывает Termux),
#      затем вTermux вставь (и нажми Enter):
#          bash ~/kodik/install.sh
#   2. Если кода в Termux ещё нет — сначала скопируй его из репозитория:
#          pkg install -y git && git clone https://github.com/....

echo "~~> Обновляю пакеты Termux..."
yes | pkg update 2>/dev/null || true
yes | pkg upgrade 2>/dev/null || true

echo "~~> Ставлю node (для opencode)…"
yes | pkg install -y nodejs-lts 2>/dev/null || yes | pkg install -y nodejs

echo "~~> Ставлю opencode…"
if ! command -v opencode >/dev/null 2>&1; then
  npm install -g opencode-ai 2>/dev/null || npm install -g opencode-ai
fi

echo "~~> Готовлю каталог ~/kodik"
mkdir -p "$HOME/kodik"
cp -f "$(dirname "$0")/start_server.sh" "$HOME/kodik/start_server.sh"
chmod +x "$HOME/kodik/start_server.sh"

echo "~~> Включаю автозапуск через Termux:Boot…"
mkdir -p "$HOME/.termux/boot"
cat > "$HOME/.termux/boot/start_kodik_server.sh" << 'BOOT_EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Автозапуск AI-сервера при загрузке телефона (нужен Termux:Boot из F-Droid).
"$HOME/kodik/start_server.sh"
BOOT_EOF
chmod +x "$HOME/.termux/boot/start_kodik_server.sh"

echo
echo "Готово! Сервер запускается прямо сейчас:"
echo "  bash ~/kodik/start_server.sh"
echo
echo "После этого в приложении жми «Проверить соединение»."
echo "А при каждой перезагрузке телефона сервер поднимется сам —"
echo "главное, чтобы был установлен и один раз открыт Termux:Boot."
