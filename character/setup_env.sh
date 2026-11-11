#!/usr/bin/env bash
# Recreates the build environment: Blender 5.2 LTS as a Python module + MediaPipe.
# usage: ./setup_env.sh [venv_dir]      then run the stages with  <venv>/bin/python scripts/NN_*.py
set -euo pipefail
VENV="${1:-.venv}"
HERE="$(cd "$(dirname "$0")" && pwd)"
python3.13 -m venv "$VENV"
"$VENV/bin/pip" install -q --upgrade pip
"$VENV/bin/pip" install -q "bpy==5.2.4" scipy pillow opencv-python-headless scikit-image matplotlib
"$VENV/bin/pip" install -q --no-deps mediapipe absl-py flatbuffers
# MediaPipe needs EGL/GLES at import time
ldconfig -p | grep -q libEGL.so.1 || (apt-get update -qq && apt-get install -y -qq --no-install-recommends libegl1 libgles2)
mkdir -p "$HERE/models" "$HERE/build"
M=https://storage.googleapis.com/mediapipe-models
[ -f "$HERE/models/face_landmarker.task" ] || curl -sS -o "$HERE/models/face_landmarker.task" "$M/face_landmarker/face_landmarker/float16/latest/face_landmarker.task"
[ -f "$HERE/models/selfie_multiclass.tflite" ] || curl -sS -o "$HERE/models/selfie_multiclass.tflite" "$M/image_segmenter/selfie_multiclass_256x256/float32/latest/selfie_multiclass_256x256.tflite"
echo "environment ready: $VENV"
