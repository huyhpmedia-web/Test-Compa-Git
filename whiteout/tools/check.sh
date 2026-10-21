#!/bin/bash
# Usage: tools/check.sh [level ids...]
# Loads every script (prints parse/compile errors) then smoke-runs each given level headless.
GODOT=${GODOT:-/tmp/claude-0/-home-user-Test-Compa-Git/b7d788c3-cd16-57ba-98fb-70cb388fdafd/scratchpad/godot/Godot_v4.5.1-stable_linux.x86_64}
DIR="$(cd "$(dirname "$0")/.." && pwd)"
timeout 180 "$GODOT" --headless --path "$DIR" --import >/dev/null 2>&1
timeout 120 "$GODOT" --headless --path "$DIR" res://tools/parse_all.tscn 2>&1 | grep -E "SCRIPT ERROR|Parse Error|Compile Error|PARSE_|^\s+at: " | grep -v -E "audio|ALSA"
for lv in "$@"; do
  echo "== smoke $lv"
  timeout 180 "$GODOT" --headless --path "$DIR" res://tools/shot.tscn -- level=$lv frames=150 2>&1 | grep -E "SCRIPT ERROR|ERROR|WARNING|SMOKE_OK|^\s+at: " | grep -v -E "audio|ALSA|alsa" | head -30
done
