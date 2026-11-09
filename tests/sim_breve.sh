#!/bin/bash
# Partite IA contro IA con diversi semi: stampa solo gli eventi principali
cd "$(dirname "$0")/.."
G=${GODOT:-godot}
for seme in "$@"; do
  for modo in base advanced; do
    echo "== seme $seme, $modo"
    NLOG=2000 timeout 900 $G --headless --path . -s res://tests/sim.gd -- $seme $modo 2>&1 | grep -E "FINE|conquistata|arrend|Pearl|entra in guerra|dichiara guerra a Unione|schiera con|ms\)$" | grep -v "^Inverno\|^Estate\|^Autunno" 
  done
done
