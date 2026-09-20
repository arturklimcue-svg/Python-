#!/data/data/com.termux/files/usr/bin/bash
# Запуск AI-сервера «КодиК» в Termux.
#
# Сервер — это opencode serve, который слушает 127.0.0.1:4096. Именно к нему
# ходит приложение «КодиК». Скрипт умеет:
#   * запускать сервер (запись 1)",
#   * останавливать (запись 2)",
#   * показывать лог (запись 3)".
#
# Чтобы сервер поднимался сам при загрузке телефона — положи этот файл в
# ~/.termux/boot/ (или включи Tерм клавиша Termux:Boot и скопируй сюда её
# `start_server.sh`). Обычный способ — просто запустить:
#
#   bash ~/kodik/start_server.sh
#
set -u

SERVER_PID=""
: ${OPCODE_PORT:=4096}

_start() {
  if curl -fsS --max-time 1 -o /dev/null "http://127.0.0.1:${OPCODE_PORT}/global/health"; then
    echo "Сервер уже запущен (127.0.0.1:${OPCODE_PORT})"
    return 0
  fi

  if ! command -v opencode >/dev/null 2>&1; then
    echo "opencode не найден. Сначала:"
    echo "  pkg install nodejs-lts && npm i -g opencode-ai"
    return 1
  fi

  echo "Стартую opencode serve на 127.0.0.1:${OPCODE_PORT}…"
  # Храним PID в файле, чтобы останавливать той же командой.
  nohup opencode serve \
    --hostname 127.0.0.1 \
    --port "${OPCODE_PORT}" \
    >"${HOME}/kodik/server.log" 2>&1 &
  SERVER_PID=$!
  echo "${SERVER_PID}" > "${HOME}/kodik/server.pid"
  echo "Запущено (PID ${SERVER_PID}). Лог: ~/kodik/server.log"
  echo "Проверка соединения в приложении: AI-чат → Настройки → Проверить."
}

_stop() {
  if [ ! -f "${HOME}/kodik/server.pid" ]; then
    echo "Сервер не запущен (нет Pid-файла)"
    return 0
  fi
  kill "$(cat "${HOME}/kodik/server.pid")" 2>/dev/null || true
  rm -f "${HOME}/kodik/server.pid"
  echo "Сервер остановлен"
}

case "${1:-start}" in
  start) _start ;;
  stop)  _stop ;;
  *)
    echo "Использование: $0 {start|stop}"
    exit 1
    ;;
esac
