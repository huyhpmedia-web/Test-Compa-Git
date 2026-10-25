#!/bin/bash
# Usage: tools/playtest.sh [level-id | all | chain | soak] [extra key=val args...]
#   tools/playtest.sh l3_church        automated critical-path playthrough of one level
#   tools/playtest.sh all              every level, one after another (each from a fresh game)
#   tools/playtest.sh chain            new game -> l1 -> ... -> l6 -> ending in ONE run
#   tools/playtest.sh soak             600-frame runtime-error soak (enemies awake) on every level
#   tools/playtest.sh soak l4_meridian same, one level
# Prints PASS/FAIL per step and a report; exit code 1 if anything failed.
GODOT=${GODOT:-/tmp/claude-0/-home-user-Test-Compa-Git/b7d788c3-cd16-57ba-98fb-70cb388fdafd/scratchpad/godot/Godot_v4.5.1-stable_linux.x86_64}
DIR="$(cd "$(dirname "$0")/.." && pwd)"
LEVELS="l1_substation l2_school l3_church l4_meridian l5_mine l6_heart"
MODE=${1:-all}
shift
run() { # run <level|chain> [args...]
  timeout ${PLAYTEST_TIMEOUT:-900} "$GODOT" --headless --fixed-fps 60 --path "$DIR" res://tools/playtest.tscn -- level=$1 "${@:2}" 2>&1 \
    | grep -v -E "ALSA|alsa|audio|^\s+at: (init_output|initialize|set_use_vsync)|V-Sync|leaked|still in use at exit|ObjectDB|cleanup \(core|clear \(core|_free_rids"
  return ${PIPESTATUS[0]}
}
rc=0
case "$MODE" in
  all)   for l in $LEVELS; do run $l "$@" || rc=1; done ;;
  chain) run chain "$@" || rc=1 ;;
  soak)  if [ -n "$1" ] && [[ "$1" != *=* ]]; then run $1 soak=1 "${@:2}" || rc=1; else for l in $LEVELS; do run $l soak=1 "$@" || rc=1; done; fi ;;
  *)     run $MODE "$@" || rc=1 ;;
esac
exit $rc
