#!/usr/bin/env bash
# Voice Transcriber: the only script you need.
#   ./start.sh            install what's missing (asks first), add the app icon, start the app
#   ./start.sh --launch   what the app icon runs: start in the background, or bring the window up
set -e
DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
cd "$DIR"
OS="$(uname -s)"
URL="http://127.0.0.1:${PORT:-7860}"

# Homebrew isn't on PATH when started from the app icon, so add it if present.
for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
  [ -x "$b" ] && eval "$("$b" shellenv)" && break
done

ask() {
  # Only ask when someone is at a terminal; otherwise answer "no".
  [ -t 0 ] || return 1
  local reply
  read -r -p "$1 [Y/n] " reply
  [[ -z "$reply" || "$reply" =~ ^[Yy] ]]
}

notify() {
  if [ "$OS" = Darwin ]; then
    osascript -e "display notification \"$1\" with title \"Voice Transcriber\"" 2>/dev/null || true
  else
    notify-send -a "Voice Transcriber" -i audio-input-microphone "Voice Transcriber" "$1" 2>/dev/null || true
  fi
}

# --- system dependency: Python 3.10+ ----------------------------------------

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

find_missing() {
  missing=()
  if [ ! -x .venv/bin/python ] && ! find_python >/dev/null; then
    missing+=(python)
  fi
}

install_system_deps() {
  find_missing
  [ ${#missing[@]} -eq 0 ] && return 0
  echo "Missing: ${missing[*]}"
  local pkgs=() cmd=() m b
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
        case "$m" in python) pkgs+=(python@3.12) ;; esac
      done
      cmd=(brew install "${pkgs[@]}")
      ;;
    Linux)
      if command -v pacman >/dev/null 2>&1; then
        cmd=(sudo pacman -S --needed --noconfirm "${missing[@]}")
      elif command -v apt-get >/dev/null 2>&1; then
        for m in "${missing[@]}"; do
          case "$m" in python) pkgs+=(python3 python3-venv) ;; esac
        done
        cmd=(sudo apt-get install -y "${pkgs[@]}")
      elif command -v dnf >/dev/null 2>&1; then
        for m in "${missing[@]}"; do
          case "$m" in python) pkgs+=(python3) ;; esac
        done
        cmd=(sudo dnf install -y "${pkgs[@]}")
      elif command -v zypper >/dev/null 2>&1; then
        for m in "${missing[@]}"; do
          case "$m" in python) pkgs+=(python3) ;; esac
        done
        cmd=(sudo zypper install -y "${pkgs[@]}")
      fi
      ;;
  esac

  if [ ${#cmd[@]} -eq 0 ]; then
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
}

# --- Python packages ---------------------------------------------------------

packages_outdated() {
  [ "$(cat .venv/.requirements 2>/dev/null)" != "$(cksum requirements.txt)" ]
}

install_packages() {
  if [ ! -x .venv/bin/python ]; then
    local py
    py="$(find_python)" || { echo "Python 3.10 or newer still not found."; exit 1; }
    echo "First run: installing Python packages with $("$py" --version)…"
    "$py" -m venv .venv
  fi
  # (re)install when requirements.txt changed, e.g. after a git pull
  packages_outdated || return 0
  echo "Installing Python packages…"
  .venv/bin/python -m pip install -q --upgrade pip
  .venv/bin/pip install -q -r requirements.txt
  if command -v nvidia-smi >/dev/null 2>&1; then
    echo "NVIDIA GPU found: installing CUDA libraries (about 2 GB)…"
    .venv/bin/pip install -q -r requirements-gpu.txt
  fi
  cksum requirements.txt > .venv/.requirements
}

# --- app icon ----------------------------------------------------------------

LINUX_APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
LINUX_DESKTOP="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"
MAC_NAME="Voice Transcriber.app"

# the installed icon's launcher file, if there is one
shortcut_file() {
  local f
  if [ "$OS" = Darwin ]; then
    for f in "/Applications/$MAC_NAME" "$HOME/Applications/$MAC_NAME"; do
      [ -f "$f/Contents/MacOS/launcher" ] && echo "$f/Contents/MacOS/launcher" && return 0
    done
  else
    f="$LINUX_APPS/voice-transcriber.desktop"
    [ -f "$f" ] && echo "$f" && return 0
  fi
  return 1
}

install_shortcut() {
  if [ "$OS" = Darwin ]; then
    # /Applications shows up in Finder's Applications list; ~/Applications
    # is the fallback when it isn't writable. Remove a copy in the other place.
    local app
    if [ -w /Applications ]; then
      app="/Applications/$MAC_NAME"; rm -rf "$HOME/Applications/$MAC_NAME"
    else
      app="$HOME/Applications/$MAC_NAME"
    fi
    rm -rf "$app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    # Assets.car: layered icon for macOS 26+ (dark, tinted, clear); icon.icns: older macOS
    cp assets/Assets.car assets/icon.icns "$app/Contents/Resources/"
    cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Voice Transcriber</string>
  <key>CFBundleDisplayName</key><string>Voice Transcriber</string>
  <key>CFBundleIdentifier</key><string>local.voice-transcriber</string>
  <key>CFBundleExecutable</key><string>launcher</string>
  <key>CFBundleIconFile</key><string>icon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
</dict>
</plist>
EOF
    cat > "$app/Contents/MacOS/launcher" <<EOF
#!/bin/bash
export VT_APP_BUNDLE="\$(cd "\$(dirname "\$0")/../.." && pwd)"
exec "$DIR/start.sh" --launch
EOF
    chmod +x "$app/Contents/MacOS/launcher"
    touch "$app"  # make Finder pick up the new icon
    [ -d "$HOME/Desktop" ] && ln -sfn "$app" "$HOME/Desktop/Voice Transcriber"
    echo "Added Voice Transcriber to Applications and the desktop."
    return 0
  fi

  local entry="[Desktop Entry]
Type=Application
Name=Voice Transcriber
Comment=Turn audio and video into text, locally
Exec=\"$DIR/start.sh\" --launch
Icon=$DIR/assets/icon.svg
Terminal=false
Categories=AudioVideo;Utility;"
  mkdir -p "$LINUX_APPS"
  printf '%s\n' "$entry" > "$LINUX_APPS/voice-transcriber.desktop"
  chmod +x "$LINUX_APPS/voice-transcriber.desktop"
  if [ -d "$LINUX_DESKTOP" ]; then
    printf '%s\n' "$entry" > "$LINUX_DESKTOP/Voice Transcriber.desktop"
    chmod +x "$LINUX_DESKTOP/Voice Transcriber.desktop"
  fi
  echo "Added Voice Transcriber to the app menu and the desktop."
}

setup_shortcut() {
  local f
  if [ "$OS" = Darwin ]; then
    # the downloaded app (from the .dmg) is installed: leave it alone
    for f in "/Applications/$MAC_NAME" "$HOME/Applications/$MAC_NAME"; do
      [ -d "$f" ] && [ ! -f "$f/Contents/MacOS/launcher" ] && return 0
    done
  fi
  if f="$(shortcut_file)"; then
    # the folder was moved, or the icon is from an older version
    grep -qF "\"$DIR/start.sh\" --launch" "$f" || install_shortcut
  elif [ ! -f .venv/.no-shortcut ] && [ -t 0 ]; then
    if ask "Add a Voice Transcriber icon to your apps and desktop?"; then
      install_shortcut
    else
      touch .venv/.no-shortcut
    fi
  fi
}

# --- running the app ---------------------------------------------------------

# macOS: when started from the .app, run a copy of Python that lives inside
# the .app. The Dock takes the app's name and icon from the bundle the running
# program is in, so otherwise it would show "Python".
mac_app_python() {
  local src lib abs host="$VT_APP_BUNDLE/Contents/MacOS/python" stamp="$VT_APP_BUNDLE/Contents/Resources/python.src"
  src="$(.venv/bin/python -c 'import sys; print(sys.base_prefix + "/Resources/Python.app/Contents/MacOS/Python")')" || return 1
  [ -f "$src" ] || return 1
  if [ ! -x "$host" ] || [ "$(cat "$stamp" 2>/dev/null)" != "$src $(cksum < "$src")" ]; then
    cp "$src" "$host.tmp" || return 1
    # it finds the Python library by a relative path; make that absolute
    lib="$(otool -L "$src" | awk '/@executable_path/ {print $1; exit}')"
    if [ -n "$lib" ]; then
      abs="$(cd "$(dirname "$src")/$(dirname "${lib#@executable_path/}")" && pwd)/$(basename "$lib")"
      install_name_tool -change "$lib" "$abs" "$host.tmp" 2>/dev/null || return 1
    fi
    codesign -f -s - "$host.tmp" 2>/dev/null || return 1
    mv "$host.tmp" "$host"
    echo "$src $(cksum < "$src")" > "$stamp"
  fi
  __PYVENV_LAUNCHER__="$PWD/.venv/bin/python" "$host" -c "import webview" 2>/dev/null || return 1
  echo "$host"
}

run_app() {
  local host
  if [ "$OS" = Darwin ] && [ -n "${VT_APP_BUNDLE:-}" ] && host="$(mac_app_python)"; then
    __PYVENV_LAUNCHER__="$PWD/.venv/bin/python" exec "$host" app.py
  fi
  exec .venv/bin/python app.py
}

# Run ./start.sh in a terminal window, so it can ask before installing things.
open_terminal() {
  if [ "$OS" = Darwin ]; then
    open -a Terminal "$DIR/start.sh" && return 0
  else
    local t
    for t in konsole gnome-terminal kitty alacritty xfce4-terminal x-terminal-emulator xterm; do
      command -v "$t" >/dev/null 2>&1 || continue
      case "$t" in
        gnome-terminal) "$t" -- "$DIR/start.sh" & ;;
        *) "$t" -e "$DIR/start.sh" & ;;
      esac
      return 0
    done
  fi
  return 1
}

# started from the app icon
launch() {
  if curl -fs -o /dev/null "$URL/api/models"; then
    local code
    code="$(curl -s -o /dev/null -w '%{http_code}' -X POST -H "X-Voice-Transcriber: 1" "$URL/api/show")"
    case "$code" in
      200) exit 0 ;;  # window brought to the front
      404)            # an older version without an app window: stop it, start this one
        curl -fs -o /dev/null -X POST -H "X-Voice-Transcriber: 1" "$URL/api/quit" || true
        for _ in 1 2 3 4 5 6 7 8 9 10; do
          curl -fs -o /dev/null "$URL/api/models" || break
          sleep 0.5
        done ;;
      *)  # running in browser mode
        if [ "$OS" = Darwin ]; then open "$URL"; else xdg-open "$URL" >/dev/null 2>&1; fi
        exit 0 ;;
    esac
  fi

  find_missing
  if [ ${#missing[@]} -gt 0 ]; then
    notify "Some things need to be installed first. Follow the steps in the terminal."
    open_terminal || notify "Open a terminal and run ./start.sh to finish the setup."
    exit 0
  fi
  packages_outdated && notify "Installing Python packages, this takes a few minutes…"

  exec >app.log 2>&1 </dev/null
  install_packages
  # exec, not background: on macOS this keeps the process tied to the .app,
  # so the Dock shows our name and icon
  run_app
}

case "${1:-}" in
  --launch) launch ;;
  "")
    install_system_deps
    install_packages
    setup_shortcut
    run_app ;;
  *) echo "Usage: ./start.sh"; exit 1 ;;
esac
