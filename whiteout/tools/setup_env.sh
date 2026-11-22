#!/bin/bash
# Rebuild the dev toolchain in a fresh cloud container (the scratchpad is wiped on restart).
#   tools/setup_env.sh <scratchpad dir>
# Installs: software Vulkan (lavapipe), Godot 4.5.1 + export templates, Blender-as-module venv (bpy 5.0.1).
set -e
S=${1:?scratchpad dir}
mkdir -p "$S/godot" "$S/charpipe"
if ! dpkg -l | grep -q mesa-vulkan-drivers; then
  apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq mesa-vulkan-drivers xvfb zip unzip >/dev/null
fi
if [ ! -x "$S/godot/Godot_v4.5.1-stable_linux.x86_64" ]; then
  curl -sSL -o "$S/godot/g.zip" https://github.com/godotengine/godot/releases/download/4.5.1-stable/Godot_v4.5.1-stable_linux.x86_64.zip
  unzip -q -o "$S/godot/g.zip" -d "$S/godot" && rm "$S/godot/g.zip"
fi
T=/root/.local/share/godot/export_templates/4.5.1.stable
if [ ! -f "$T/windows_release_x86_64.exe" ]; then
  mkdir -p "$T"
  curl -sSL -o "$S/godot/t.tpz" https://github.com/godotengine/godot/releases/download/4.5.1-stable/Godot_v4.5.1-stable_export_templates.tpz
  unzip -q -o "$S/godot/t.tpz" -d "$S/godot/tpl" && cp "$S"/godot/tpl/templates/windows_release_x86_64.exe "$S"/godot/tpl/templates/version.txt "$T"/ && rm -rf "$S/godot/t.tpz" "$S/godot/tpl"
fi
if [ ! -x "$S/charpipe/venv/bin/python" ]; then
  (cd "$S/charpipe" && uv python install 3.11 -q && uv venv -q --python 3.11 venv && uv pip install -q --python venv/bin/python bpy==5.0.1 numpy pillow)
fi
echo "toolchain ready in $S"
