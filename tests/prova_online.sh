#!/bin/bash
# Prova online completa: finto Firebase + due istanze di Godot (host e ospite).
# Uso: GODOT=/percorso/godot tests/prova_online.sh
cd "$(dirname "$0")/.."
G=${GODOT:-godot}
python3 tests/firebase_mock.py 8765 > /tmp/mock.log 2>&1 &
MOCK=$!
sleep 1
export FR_DB_URL=http://127.0.0.1:8765/db FR_AUTH_URL=http://127.0.0.1:8765/signup FR_REFRESH_URL=http://127.0.0.1:8765/refresh
rm -f /tmp/tr_code /tmp/tr_host.cfg /tmp/tr_guest.cfg
TR_ROLE=host TR_CODEFILE=/tmp/tr_code FR_SESSION=/tmp/tr_host.cfg timeout 900 $G --headless --path . -s res://tests/online_auto.gd > /tmp/host.log 2>&1 &
H=$!
TR_ROLE=guest TR_CODEFILE=/tmp/tr_code FR_SESSION=/tmp/tr_guest.cfg timeout 900 $G --headless --path . -s res://tests/online_auto.gd > /tmp/guest.log 2>&1 &
O=$!
wait $H $O
kill $MOCK
grep "TR " /tmp/host.log /tmp/guest.log
