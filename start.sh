#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"

# --- system dependencies: ffmpeg and Python 3.10+ ---------------------------

OS="$(uname -s)"

# Homebrew isn't on PATH when started from a launcher, so add it if present.
for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
  [ -x "$b" ] && eval "$("$b" shellenv)" && break
done

find_python() {
  local p
  for p in python3.13 python3.12 python3.11 python3.10 python3; do
    if command -v "$p" >/dev/null 2>&1 &&
       "$p" -c 'import sys, ensurepip; sys.exit(sys.version_info < (3, 10))' 2>/dev/null; then
      command -v "$p"
      return 0
    fi
  done
  return 1
}

ask() {
  # Only ask when someone is at a terminal; otherwise answer "no".
  [ -t 0 ] || return 1
  local reply
  read -r -p "$1 [Y/n] " reply
  [[ -z "$reply" || "$reply" =~ ^[Yy] ]]
}

missing=()
command -v ffmpeg >/dev/null 2>&1 || missing+=(ffmpeg)
if [ ! -x .venv/bin/python ] && ! find_python >/dev/null; then
  missing+=(python)
fi

# --check: only report, used by launch.sh to decide if a terminal is needed
if [ "${1:-}" = --check ]; then
  [ ${#missing[@]} -eq 0 ] && exit 0
  echo "Missing: ${missing[*]}"
  exit 1
fi

if [ ${#missing[@]} -gt 0 ]; then
  echo "Missing: ${missing[*]}"
  pkgs=()
  case "$OS" in
    Darwin)
      if ! command -v brew >/dev/null 2>&1; then
        echo "Homebrew (https://brew.sh) is needed to install them."
        if ask "Install Homebrew now?"; then
          /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
          for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
            [ -x "$b" ] && eval "$("$b" shellenv)" && break
          done
        else
          echo "Install Homebrew, then run ./start.sh again."
          exit 1
        fi
      fi
      for m in "${missing[@]}"; do
        case "$m" in ffmpeg) pkgs+=(ffmpeg) ;; python) pkgs+=(python@3.12) ;; esac
      done
      cmd=(brew install "${pkgs[@]}")
      ;;
    Linux)
      if command -v pacman >/dev/null 2>&1; then
        for m in "${missing[@]}"; do pkgs+=("$m"); done
        cmd=(sudo pacman -S --needed --noconfirm "${pkgs[@]}")
      elif command -v apt-get >/dev/null 2>&1; then
        for m in "${missing[@]}"; do
          case "$m" in ffmpeg) pkgs+=(ffmpeg) ;; python) pkgs+=(python3 python3-venv) ;; esac
        done
        cmd=(sudo apt-get install -y "${pkgs[@]}")
      elif command -v dnf >/dev/null 2>&1; then
        for m in "${missing[@]}"; do
          case "$m" in ffmpeg) pkgs+=(ffmpeg-free) ;; python) pkgs+=(python3) ;; esac
        done
        cmd=(sudo dnf install -y "${pkgs[@]}")
      elif command -v zypper >/dev/null 2>&1; then
        for m in "${missing[@]}"; do
          case "$m" in ffmpeg) pkgs+=(ffmpeg) ;; python) pkgs+=(python3) ;; esac
        done
        cmd=(sudo zypper install -y "${pkgs[@]}")
      fi
      ;;
  esac

  if [ -z "${cmd+x}" ]; then
    echo "Please install ${missing[*]} (Python 3.10 or newer) yourself, then run ./start.sh again."
    exit 1
  fi
  echo "This will run: ${cmd[*]}"
  if ask "Install now?"; then
    "${cmd[@]}"
  else
    echo "Run that command yourself, then run ./start.sh again."
    exit 1
  fi

  command -v ffmpeg >/dev/null 2>&1 || { echo "ffmpeg still not found."; exit 1; }
fi

# --- Python packages ---------------------------------------------------------

if [ ! -x .venv/bin/python ]; then
  PY="$(find_python)" || { echo "Python 3.10 or newer still not found."; exit 1; }
  echo "First run: installing Python packages with $("$PY" --version)…"
  "$PY" -m venv .venv
  .venv/bin/pip install -q -r requirements.txt
  if command -v nvidia-smi >/dev/null 2>&1; then
    echo "NVIDIA GPU found: installing CUDA libraries (~1 GB)…"
    .venv/bin/pip install -q -r requirements-gpu.txt
  fi
fi
exec .venv/bin/python app.py
