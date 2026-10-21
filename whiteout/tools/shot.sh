#!/bin/bash
# Usage: tools/shot.sh <level> <out.png> [extra key=val args...]
# Renders a screenshot of a level with the Forward+ renderer under Xvfb (software Vulkan).
GODOT=${GODOT:-/tmp/claude-0/-home-user-Test-Compa-Git/b7d788c3-cd16-57ba-98fb-70cb388fdafd/scratchpad/godot/Godot_v4.5.1-stable_linux.x86_64}
DIR="$(cd "$(dirname "$0")/.." && pwd)"
LEVEL=$1; OUT=$2; shift 2
timeout 240 xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path "$DIR" --resolution 1280x720 res://tools/shot.tscn -- level=$LEVEL out=$OUT "$@" 2>&1 | grep -v -E "ALSA|audio|alsa|^\s+at: (init_output|initialize|set_use_vsync)|V-Sync" 
