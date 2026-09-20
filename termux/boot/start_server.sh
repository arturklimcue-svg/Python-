#!/data/data/com.termux/files/usr/bin/bash
# Termux:Boot — автозапуск AI-сервера «КодиК» при загрузке телефона.
#
# ЭТОТ ФАЙЛ должен лежать ВНУТРИ Termux по пути:
#   ~/.termux/boot/start_server.sh
# и тогда Termux:Boot поднимет сервер сам, как только телефон включили —
# Termux и «КодиК» больше не нужно открывать вручную.
#
# Установка в одну команду (из Termux):
#   bash ~/kodik/install.sh
#
exec "${HOME}/kodik/start_server.sh" start
