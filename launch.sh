#!/usr/bin/env bash
# shortcut target: start the app, or bring its window to the front if it's already running
cd "$(dirname "$(readlink -f "$0")")"
URL="http://127.0.0.1:${PORT:-7860}"
OS="$(uname -s)"

open_url() {
  if [ "$OS" = Darwin ]; then open "$1"; else xdg-open "$1" >/dev/null 2>&1; fi
}

notify() {
  if [ "$OS" = Darwin ]; then
    osascript -e "display notification \"$1\" with title \"Voice Transcriber\"" 2>/dev/null || true
  else
    notify-send -a "Voice Transcriber" -i audio-input-microphone "Voice Transcriber" "$1" 2>/dev/null || true
  fi
}

# Run start.sh in a terminal window, so it can ask before installing things.
open_terminal() {
  if [ "$OS" = Darwin ]; then
    open -a Terminal "$PWD/start.sh" && return 0
  else
    local t
    for t in konsole gnome-terminal kitty alacritty xfce4-terminal x-terminal-emulator xterm; do
      command -v "$t" >/dev/null 2>&1 || continue
      case "$t" in
        gnome-terminal) "$t" -- "$PWD/start.sh" & ;;
        *) "$t" -e "$PWD/start.sh" & ;;
      esac
      return 0
    done
  fi
  return 1
}

if curl -fs -o /dev/null "$URL/api/models"; then
  curl -fs -o /dev/null -X POST -H "X-Voice-Transcriber: 1" "$URL/api/show" || open_url "$URL"
  exit 0
fi

if ! ./start.sh --check >/dev/null 2>&1; then
  notify "Some things need to be installed first. Follow the steps in the terminal."
  open_terminal || notify "Open a terminal and run ./start.sh to finish the setup."
  exit 0
fi

if [ "$(cat .venv/.requirements 2>/dev/null)" != "$(cksum requirements.txt)" ]; then
  notify "Installing Python packages, this takes a few minutes…"
fi
# exec, not background: on macOS this keeps the process tied to the .app,
# so the Dock shows our name and icon
exec ./start.sh >app.log 2>&1 </dev/null
