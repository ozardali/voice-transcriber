#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
if [ ! -x .venv/bin/python ]; then
  echo "First run: installing dependencies…"
  python3 -m venv .venv
  .venv/bin/pip install -q -r requirements.txt
  if command -v nvidia-smi >/dev/null 2>&1; then
    echo "NVIDIA GPU found: installing CUDA libraries (~1 GB)…"
    .venv/bin/pip install -q -r requirements-gpu.txt
  fi
fi
exec .venv/bin/python app.py
